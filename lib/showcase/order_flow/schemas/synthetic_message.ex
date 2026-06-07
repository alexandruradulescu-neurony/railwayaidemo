defmodule Showcase.OrderFlow.Schemas.SyntheticMessage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "of_synthetic_messages" do
    field :body, :string
    field :kind, :string
    field :scenario, :string
    field :client_hint, :string
    field :from_address, :string
    field :subject, :string
    field :attachment_paths, {:array, :string}, default: []
    field :composed, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for SEEDED messages — scenario required, kind constrained to
  email/whatsapp (used by the seed loop).
  """
  def changeset(msg, attrs) do
    msg
    |> cast(attrs, [
      :body,
      :kind,
      :scenario,
      :client_hint,
      :from_address,
      :subject,
      :attachment_paths,
      :composed
    ])
    |> validate_required([:body, :kind, :scenario])
    |> validate_inclusion(:kind, ["email", "whatsapp"])
  end

  @doc """
  Changeset for COMPOSED messages from the in-app Gmail-style modal.

  Doesn't require `scenario` (composed messages hit real Claude — there's no
  scripted response). Defaults kind to "email" and composed to true.

  Body OR at least one attachment must be present — sending a PDF with no
  body text is a valid use case ("here's the order, see attached").
  """
  def compose_changeset(msg, attrs) do
    # `:attachment_paths` is NOT cast from `attrs` — a hand-crafted POST to a
    # websocket event could otherwise inject arbitrary path strings, and
    # `Extraction` would dutifully try to read them as PDFs. The LiveView
    # passes the consumed-upload paths via the dedicated `attachment_paths`
    # atom key (form params are string-keyed, so they can't collide with the
    # atom lookup below). See REVIEW.md MED-07.
    msg
    |> cast(attrs, [:body, :subject, :from_address])
    |> put_change(:attachment_paths, Map.get(attrs, :attachment_paths, []))
    |> put_change(:kind, "email")
    |> put_change(:composed, true)
    |> put_change(:scenario, nil)
    # Ecto's `cast` turns empty form strings into nil. The DB column is
    # `NOT NULL`, so an empty body would silently fail at insert time —
    # coerce nil back to "" so PDF-only emails persist cleanly.
    |> ensure_body_string()
    |> validate_required([:from_address])
    |> validate_body_or_attachment()
    |> validate_length(:from_address, max: 200)
    |> validate_length(:subject, max: 200)
  end

  defp ensure_body_string(changeset) do
    case get_field(changeset, :body) do
      nil -> put_change(changeset, :body, "")
      _ -> changeset
    end
  end

  defp validate_body_or_attachment(changeset) do
    body = changeset |> get_field(:body) |> to_string() |> String.trim()
    attachments = get_field(changeset, :attachment_paths) || []

    if body == "" and attachments == [] do
      add_error(changeset, :body, "must include either body text or at least one attachment")
    else
      changeset
    end
  end
end
