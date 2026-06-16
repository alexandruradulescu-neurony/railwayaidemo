defmodule Showcase.OrderFlow.Extraction do
  @moduledoc """
  Boundary that produces `{client_hint, lines}` from a raw customer message.

  Two modes:

    * **Scripted** (seeded messages — `composed: false`): looks up the
      canned JSON in `MockPrompts.extract_text_for/1` and returns it without
      calling Anthropic. Keeps the live demo predictable regardless of
      whether the `Live` or `Mock` AnthropicClient impl is configured.
    * **Real** (composed messages from the in-app email modal): calls
      `AnthropicClient.call/2`, optionally with image attachments as Vision
      content blocks. Returns whatever Claude produces.

  Expected response shape:
    {"client_hint": "...", "lines": [{"description": "...", "quantity": N}, ...]}

  Returns `{:ok, %{client_hint, lines}}` or `{:error, reason}`.
  """

  alias Showcase.Common.AnthropicClient
  alias Showcase.Common.AnthropicClient.Types.Request
  alias Showcase.Common.Config
  alias Showcase.Common.ResilientJSONParser
  alias Showcase.OrderFlow.MockPrompts
  alias Showcase.OrderFlow.Schemas.SyntheticMessage

  @fingerprint "order_flow:extract:v1"
  @system_prompt """
  You parse a customer order message into structured data.

  Respond with JSON ONLY in this shape:
    {"client_hint": "<name as customer mentions or implies, or null>",
     "lines": [{"description": "<product name as written>", "quantity": <integer>}, ...]}

  If the message references attached images (e.g. a handwritten note or
  photo of a list), read what you can see and merge it into `lines`.

  Do not invent. Do not include narration outside the JSON.
  """

  @type extracted_line :: %{description: String.t(), quantity: integer()}
  @type extracted :: %{client_hint: String.t() | nil, lines: list(extracted_line())}

  @doc "The active system prompt text. Exposed for SystemPromptSeeder."
  @spec system_prompt() :: String.t()
  def system_prompt, do: @system_prompt

  @doc """
  Extract from a SyntheticMessage. Picks scripted vs real-AnthropicClient
  based on `msg.composed`.
  """
  @spec extract_message(SyntheticMessage.t()) :: {:ok, extracted()} | {:error, term()}
  def extract_message(%SyntheticMessage{composed: true} = msg) do
    extract_real(msg.body, msg.attachment_paths || [], scenario: msg.scenario)
  end

  def extract_message(%SyntheticMessage{composed: false} = msg) do
    case MockPrompts.extract_text_for(msg.scenario) do
      {:ok, text} ->
        parse_extracted(text)

      :not_found ->
        # Test-local scenarios or future seeded messages without a scripted
        # entry — fall through to AnthropicClient (Mock impl in tests,
        # Live in dev with a real API key).
        extract_real(msg.body, msg.attachment_paths || [], scenario: msg.scenario)
    end
  end

  @doc """
  Legacy entry point — still exposed for tests / callers that pass raw body.
  Always hits the configured AnthropicClient impl.
  """
  @spec extract(String.t(), keyword()) :: {:ok, extracted()} | {:error, term()}
  def extract(body, opts \\ []) when is_binary(body) do
    extract_real(body, [], opts)
  end

  defp extract_real(body, attachment_paths, opts) do
    scenario = Keyword.get(opts, :scenario)

    user_content = build_user_content(body, attachment_paths)

    req = %Request{
      model: Config.default_model(),
      messages: [%{role: "user", content: user_content}],
      system: @system_prompt,
      metadata: %{fingerprint: @fingerprint, scenario: scenario}
    }

    case AnthropicClient.call(req) do
      {:ok, response} -> parse_extracted(response.text)
      {:error, _} = err -> err
    end
  end

  # Pure text → string content (Anthropic accepts the shorthand).
  # Text + attachments → list of content blocks (vision/document payload).
  defp build_user_content(body, []), do: body || ""

  defp build_user_content(body, paths) when is_list(paths) do
    blocks =
      paths
      |> Enum.map(&read_attachment_block/1)
      |> Enum.reject(&is_nil/1)

    case blocks do
      [] ->
        body || ""

      blocks ->
        # If the body is empty (e.g. "here's the order, see PDF"), give
        # Claude a one-liner instructing it to read from the attachment(s).
        # Anthropic rejects empty text blocks.
        body_text =
          case body |> to_string() |> String.trim() do
            "" -> "Order details are in the attached file(s). Extract the line items."
            non_empty -> non_empty
          end

        blocks ++ [%{type: "text", text: body_text}]
    end
  end

  # Branch on extension: PDFs become `document` content blocks (Claude reads
  # them natively — text + embedded images + handwriting). Everything else
  # falls through to `image` blocks.
  defp read_attachment_block(path) when is_binary(path) do
    case File.read(Showcase.Uploads.resolve(path)) do
      {:ok, bytes} ->
        if pdf?(path) do
          %{
            type: "document",
            source: %{
              type: "base64",
              media_type: "application/pdf",
              data: Base.encode64(bytes)
            }
          }
        else
          %{
            type: "image",
            source: %{
              type: "base64",
              media_type: image_media_type_for(path),
              data: Base.encode64(bytes)
            }
          }
        end

      {:error, _} ->
        nil
    end
  end

  defp read_attachment_block(_), do: nil

  defp pdf?(path), do: String.downcase(Path.extname(path)) == ".pdf"

  defp image_media_type_for(path) do
    case path |> Path.extname() |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "image/png"
    end
  end

  defp parse_extracted(text) when is_binary(text) do
    with {:ok, raw, _completeness} <- ResilientJSONParser.parse(text) do
      parsed = %{
        client_hint: Map.get(raw, "client_hint"),
        lines:
          raw
          |> Map.get("lines", [])
          |> Enum.map(fn line ->
            %{
              description: Map.get(line, "description"),
              quantity: Map.get(line, "quantity")
            }
          end)
          |> Enum.filter(fn line ->
            is_binary(line.description) and is_integer(line.quantity)
          end)
      }

      {:ok, parsed}
    end
  end
end
