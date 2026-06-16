defmodule Showcase.OrderFlow do
  @moduledoc """
  Public context for the OrderFlow demo.

  Used by LiveViews to:
    * compose new emails (Gmail-style modal) → `create_composed_message/1`
    * enqueue analysis for a specific message → `enqueue_analysis/1`
    * list inbox messages and find orders
    * delete messages
  Used by tests to bulk-register mock Anthropic responses.
  """

  import Ecto.Query

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.OrderFlow.MockPrompts
  alias Showcase.OrderFlow.Schemas.{Order, ProductAlias, SyntheticMessage}
  alias Showcase.OrderFlow.Worker
  alias Showcase.Repo

  @doc """
  Look up the global (client_id IS NULL) `ProductAlias` row for a
  given normalized text + product. Returns the alias struct or `nil`.

  Centralizes a query open-coded in 4 places — easy to drift, e.g. one
  callsite filtering `not is_nil(client_id)` instead. See REVIEW.md MED-05.
  """
  @spec find_global_alias(String.t(), integer()) :: ProductAlias.t() | nil
  def find_global_alias(normalized_text, product_id) do
    Repo.one(
      from a in ProductAlias,
        where:
          a.normalized_text == ^normalized_text and
            a.product_id == ^product_id and
            is_nil(a.client_id)
    )
  end

  # Resolved at runtime so the release's UPLOADS_ROOT env var (set on
  # Railway to match the volume mount path) is honored.
  defp upload_dir do
    Path.join(
      Application.get_env(:showcase, :uploads_root, "priv/static/uploads"),
      "order_flow"
    )
  end

  @upload_url_prefix "/uploads/order_flow"

  @doc """
  Enqueue analysis for a specific message id. Used by the click-to-analyze
  flow in the new 3-pane inbox.
  """
  @spec enqueue_analysis(integer()) ::
          {:ok, Oban.Job.t(), SyntheticMessage.t()} | {:error, term()}
  def enqueue_analysis(message_id) do
    case Repo.get(SyntheticMessage, message_id) do
      nil ->
        {:error, :not_found}

      %SyntheticMessage{} = msg ->
        {:ok, job} = Worker.new(%{message_id: msg.id}) |> Oban.insert()
        {:ok, job, msg}
    end
  end

  @doc """
  Legacy entry point — enqueue a random unprocessed seeded message. Still
  used by the older "Generate order" button path if anything calls it.
  """
  @spec enqueue_random() ::
          {:ok, Oban.Job.t(), SyntheticMessage.t()} | {:error, :no_messages}
  def enqueue_random do
    case unprocessed_messages() do
      [] ->
        {:error, :no_messages}

      msgs ->
        msg = Enum.random(msgs)
        {:ok, job} = Worker.new(%{message_id: msg.id}) |> Oban.insert()
        {:ok, job, msg}
    end
  end

  defp unprocessed_messages do
    subquery =
      from o in Order,
        where: not is_nil(o.synthetic_message_id),
        select: o.synthetic_message_id

    from(m in SyntheticMessage,
      where: m.id not in subquery(subquery)
    )
    |> Repo.all()
  end

  @doc "Has this message already been processed into an Order?"
  @spec processed?(SyntheticMessage.t()) :: boolean()
  def processed?(%SyntheticMessage{id: id}) do
    Repo.exists?(from o in Order, where: o.synthetic_message_id == ^id)
  end

  @doc """
  Insert a composed (user-typed) SyntheticMessage. Bypasses seed-style
  validation — no scenario required.
  """
  @spec create_composed_message(map()) ::
          {:ok, SyntheticMessage.t()} | {:error, Ecto.Changeset.t()}
  def create_composed_message(attrs) do
    %SyntheticMessage{}
    |> SyntheticMessage.compose_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Delete a message (and cascade its order via the FK). Cleans up attached
  files on disk too.
  """
  @spec delete_message(integer() | SyntheticMessage.t()) ::
          {:ok, SyntheticMessage.t()} | {:error, term()}
  def delete_message(%SyntheticMessage{} = msg) do
    # Wrap the FK null-out + delete in a transaction so a half-finished
    # delete can't leave orphan orders or claim "deleted" without it.
    # Files on disk are removed AFTER the DB transaction commits — see
    # REVIEW.md MED-04.
    Repo.transaction(fn ->
      from(o in Order, where: o.synthetic_message_id == ^msg.id)
      |> Repo.update_all(set: [synthetic_message_id: nil])

      Repo.delete!(msg)
    end)
    |> case do
      {:ok, _} ->
        Enum.each(msg.attachment_paths || [], &delete_upload/1)
        {:ok, msg}

      {:error, _} = err ->
        err
    end
  end

  def delete_message(id) when is_integer(id) do
    case Repo.get(SyntheticMessage, id) do
      nil -> {:error, :not_found}
      msg -> delete_message(msg)
    end
  end

  @doc """
  Persist an uploaded attachment to disk and return its web-relative path.
  Caller is expected to merge the path into the message's `attachment_paths`.
  """
  @spec save_attachment(Path.t(), String.t()) :: String.t()
  def save_attachment(temp_path, original_name) do
    File.mkdir_p!(upload_dir())
    ext = original_name |> Path.extname() |> String.downcase()
    filename = "#{System.unique_integer([:positive])}-#{:erlang.unique_integer([:positive])}#{ext}"
    dest = Path.join(upload_dir(), filename)
    File.cp!(temp_path, dest)
    "#{@upload_url_prefix}/#{filename}"
  end

  defp delete_upload(path) when is_binary(path) do
    # Strip the "/uploads/" prefix and resolve against uploads_root so
    # the deletion finds files in the volume mount path (Railway) or the
    # repo-relative uploads dir (dev).
    root = Application.get_env(:showcase, :uploads_root, "priv/static/uploads")
    rel = path |> String.trim_leading("/uploads/") |> String.trim_leading("/")
    File.rm(Path.join(root, rel))
  end

  defp delete_upload(_), do: :ok

  @doc "All seeded synthetic messages, newest first (composed at top)."
  def list_messages do
    Repo.all(from m in SyntheticMessage, order_by: [desc: m.inserted_at])
  end

  @doc """
  Return a map from `message_id -> %{order_status, matched, total}` for
  every message that has an order. Used by the inbox list to render badges
  without N+1 queries.

  Messages without an order get no entry in the map (callers treat that as
  "not analyzed").
  """
  @spec order_status_by_message() :: %{
          optional(integer()) => %{
            order_id: integer(),
            order_status: String.t(),
            matched: integer(),
            total: integer(),
            client_id: integer() | nil
          }
        }
  def order_status_by_message do
    line_counts =
      from ol in Showcase.OrderFlow.Schemas.OrderLine,
        group_by: ol.order_id,
        select: %{
          order_id: ol.order_id,
          total: count(ol.id),
          matched: fragment("count(?) filter (where ? is not null)", ol.id, ol.product_id)
        }

    from(o in Order,
      where: not is_nil(o.synthetic_message_id),
      left_join: lc in subquery(line_counts),
      on: lc.order_id == o.id,
      select: %{
        message_id: o.synthetic_message_id,
        order_id: o.id,
        order_status: o.status,
        client_id: o.client_id,
        matched: coalesce(lc.matched, 0),
        total: coalesce(lc.total, 0)
      }
    )
    |> Repo.all()
    |> Map.new(fn row -> {row.message_id, Map.delete(row, :message_id)} end)
  end

  @doc """
  Rebuild the cascade `line_matched` event list from persisted `OrderLine`
  rows. Returns the same shape as the live PubSub events so the LiveView
  can populate "Show cascade detail" when the user re-opens a previously
  analyzed message.
  """
  @spec cascade_events_for_order(Order.t() | nil) :: [map()]
  def cascade_events_for_order(nil), do: []

  def cascade_events_for_order(%Order{} = order) do
    order = if Ecto.assoc_loaded?(order.lines), do: order, else: Repo.preload(order, :lines)

    Enum.map(order.lines, fn line ->
      %{
        description: line.raw_description,
        step: line.match_step && String.to_atom(line.match_step),
        confidence: line.confidence,
        matched: not is_nil(line.product_id)
      }
    end)
  end

  @doc "Fetch a single message by id."
  def get_message!(id), do: Repo.get!(SyntheticMessage, id)
  def get_message(id), do: Repo.get(SyntheticMessage, id)

  @doc "Find the order for a given message, if any."
  def order_for_message(message_id) do
    Repo.one(
      from o in Order,
        where: o.synthetic_message_id == ^message_id,
        preload: [:client, lines: :product]
    )
  end

  @doc "All orders, most recent first."
  def list_orders do
    from(o in Order, order_by: [desc: o.inserted_at], preload: [:client, lines: :product])
    |> Repo.all()
  end

  @doc "Fetch an order with its lines + client."
  def find_order(id) do
    Repo.get(Order, id) |> Repo.preload([:client, lines: :product])
  end

  @doc """
  Mark an order as sent to the ERP. Idempotent — calling twice is a no-op.
  Returns the updated order.
  """
  @spec mark_sent_to_erp(Order.t() | integer()) :: {:ok, Order.t()} | {:error, term()}
  def mark_sent_to_erp(%Order{} = order) do
    order
    |> Order.changeset(%{status: "sent_to_erp"})
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, Repo.preload(updated, [:client, lines: :product])}
      err -> err
    end
  end

  def mark_sent_to_erp(id) when is_integer(id) do
    case Repo.get(Order, id) do
      nil -> {:error, :not_found}
      order -> mark_sent_to_erp(order)
    end
  end

  @doc """
  Generate a fake ERP reference string from an order ID for the demo's
  "Send to ERP" confirmation. Deterministic so re-renders show the same ref.

      iex> Showcase.OrderFlow.erp_reference(125)
      "ERP-2026-000125"
  """
  @spec erp_reference(integer() | Order.t()) :: String.t()
  def erp_reference(%Order{id: id}), do: erp_reference(id)

  def erp_reference(id) when is_integer(id) do
    "ERP-2026-#{id |> to_string() |> String.pad_leading(6, "0")}"
  end

  @doc """
  Create a brand-new Product on the fly from an unmatched OrderLine. Wires
  up the line, seeds a global alias (so future runs of the same raw text
  auto-match without an LLM call), and returns the new product + updated
  line.

  This is the "Add to catalog" escape hatch when the AI couldn't match a
  line because the product genuinely doesn't exist in the catalog yet.
  Demonstrates the second self-improving angle: corrections teach aliases,
  but new-product additions grow the catalog itself.
  """
  @spec create_product_for_line(Showcase.OrderFlow.Schemas.OrderLine.t()) ::
          {:ok, %{product: Showcase.OrderFlow.Schemas.Product.t(), line: Showcase.OrderFlow.Schemas.OrderLine.t()}}
          | {:error, term()}
  def create_product_for_line(%Showcase.OrderFlow.Schemas.OrderLine{} = line) do
    alias Showcase.OrderFlow.Impl.Normalize
    alias Showcase.OrderFlow.Schemas.{OrderLine, Product, ProductAlias}

    raw = line.raw_description || ""
    sku = "NEW-#{line.id}"
    normalized = Normalize.normalize_text(raw)

    Repo.transaction(fn ->
      product =
        Repo.get_by(Product, sku: sku) ||
          (%Product{}
           |> Product.changeset(%{
             sku: sku,
             name: raw,
             normalized_name: normalized
           })
           |> Repo.insert!())

      updated_line =
        line
        |> OrderLine.changeset(%{
          product_id: product.id,
          match_step: "manual_catalog",
          confidence: 1.0
        })
        |> Repo.update!()

      now = DateTime.utc_now()

      existing_alias = find_global_alias(normalized, product.id)

      unless existing_alias do
        %ProductAlias{}
        |> ProductAlias.changeset(%{
          normalized_text: normalized,
          product_id: product.id,
          client_id: nil,
          confidence: 1.0,
          last_used_at: now,
          use_count: 1,
          source: "manual_catalog"
        })
        |> Repo.insert!()
      end

      %{product: product, line: updated_line}
    end)
  end

  @doc """
  Register mock responses for every scenario in `MockPrompts.scenarios/0`.
  Call from test setup (only the Mock impl is active in test env).
  """
  def register_mock_responses do
    Enum.each(MockPrompts.scenarios(), fn s ->
      Mock.register("order_flow:extract:v1",
        scenario: s.name,
        text: s.extract_response
      )

      Enum.each(s.fallback_responses, fn fr ->
        Mock.register("order_flow:claude_fallback:v1",
          scenario: fr.scenario,
          text: fr.text
        )
      end)
    end)
  end
end
