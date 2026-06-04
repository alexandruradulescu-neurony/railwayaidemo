defmodule Showcase.RecruitFlow.Impl.StateMachine do
  @moduledoc """
  Pure 5-state machine for RecruitFlow Applications.

  States:
    * `PENDING` — initial; awaiting AI screen, or callback requested.
    * `QUALIFIED` — AI screen positive, awaiting CV.
    * `HIRED` — CV matched (terminal).
    * `REJECTED` — AI screen negative or stale (terminal).
    * `NEEDS_HUMAN` — AI uncertain (terminal).

  Transitions:
    * `PENDING` → `QUALIFIED | REJECTED | NEEDS_HUMAN | PENDING`
      (the self-loop handles callback outcomes — state stays but audit entry logged)
    * `QUALIFIED` → `HIRED | REJECTED`
    * Terminal states have no outgoing.
  """

  @transitions %{
    "PENDING" => ["PENDING", "QUALIFIED", "REJECTED", "NEEDS_HUMAN"],
    "QUALIFIED" => ["HIRED", "REJECTED"],
    "HIRED" => [],
    "REJECTED" => [],
    "NEEDS_HUMAN" => []
  }

  @states Map.keys(@transitions)

  @doc "All 5 states."
  @spec states() :: list(String.t())
  def states, do: @states

  @doc "Allowed next states from `state`. `[]` if state is unknown or terminal."
  @spec next(String.t()) :: list(String.t())
  def next(state), do: Map.get(@transitions, state, [])

  @doc "Is the transition `from → to` allowed?"
  @spec allowed?(String.t(), String.t()) :: boolean()
  def allowed?(from, to), do: to in next(from)

  @doc "Is `state` terminal (no outgoing transitions)?"
  @spec terminal?(String.t()) :: boolean()
  def terminal?(state), do: state in ~w(HIRED REJECTED NEEDS_HUMAN)
end
