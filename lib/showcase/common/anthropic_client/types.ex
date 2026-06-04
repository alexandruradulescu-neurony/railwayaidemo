defmodule Showcase.Common.AnthropicClient.Types do
  @moduledoc """
  Structs for AnthropicClient request/response.
  """

  defmodule Request do
    @moduledoc false
    @enforce_keys [:model, :messages]
    defstruct [
      :model,
      :messages,
      :system,
      :max_tokens,
      :temperature,
      :metadata,
      tools: [],
      tool_choice: nil
    ]

    @type t :: %__MODULE__{
            model: String.t(),
            messages: list(map()),
            system: String.t() | nil,
            max_tokens: pos_integer() | nil,
            temperature: float() | nil,
            metadata: map() | nil,
            tools: list(map()),
            tool_choice: map() | nil
          }
  end

  defmodule Usage do
    @moduledoc false
    defstruct input_tokens: 0, output_tokens: 0, cost_estimate_cents: 0.0

    @type t :: %__MODULE__{
            input_tokens: non_neg_integer(),
            output_tokens: non_neg_integer(),
            cost_estimate_cents: float()
          }
  end

  defmodule Response do
    @moduledoc false
    @enforce_keys [:text, :usage]
    defstruct [:text, :usage, :stop_reason, :raw]

    @type t :: %__MODULE__{
            text: String.t(),
            usage: Usage.t(),
            stop_reason: atom() | String.t() | nil,
            raw: map() | nil
          }
  end
end
