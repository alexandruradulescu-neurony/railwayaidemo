defmodule Showcase.Common.NeedsHuman do
  @moduledoc """
  Standard "escalate to human" outcome shape used by every demo.

  Each demo's pipeline ultimately returns a result that includes a
  `%NeedsHuman.Decision{}` so the shared `NeedsHumanBadge` component renders
  identically across demos. Repetition is the teaching point.
  """

  defmodule Decision do
    @enforce_keys [:needs_review?]
    defstruct [:needs_review?, reasons: [], confidence: nil, source: nil]

    @type t :: %__MODULE__{
            needs_review?: boolean(),
            reasons: list(String.t()),
            confidence: float() | nil,
            source: atom() | nil
          }
  end

  @doc """
  Returns a "no review needed" decision.
  """
  @spec ok() :: Decision.t()
  def ok, do: %Decision{needs_review?: false}

  @doc """
  Returns an "escalate" decision with reasons.
  """
  @spec escalate([String.t()], keyword()) :: Decision.t()
  def escalate(reasons, opts \\ []) when is_list(reasons) do
    %Decision{
      needs_review?: true,
      reasons: reasons,
      confidence: Keyword.get(opts, :confidence),
      source: Keyword.get(opts, :source)
    }
  end

  @doc """
  Convenience: escalate if confidence below threshold.
  """
  @spec from_confidence(float(), float(), atom()) :: Decision.t()
  def from_confidence(confidence, threshold, source) when confidence < threshold do
    escalate(
      ["confidence #{Float.round(confidence, 2)} below threshold #{threshold}"],
      confidence: confidence,
      source: source
    )
  end

  def from_confidence(_confidence, _threshold, _source), do: ok()
end
