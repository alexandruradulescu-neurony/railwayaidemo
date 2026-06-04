defmodule Showcase.RecruitFlow.Transitions do
  @moduledoc """
  Boundary that owns state transitions for RecruitFlow Applications.

  Every transition:
    1. Verifies StateMachine.allowed?(from, to).
    2. Updates Application (state + state_changed_at + optionally transcript/eval).
    3. Writes a Common.AuditLog entry with payload %{from, to, reason} (post-tx).
    4. Broadcasts {:recruit_flow, :transitioned, _} on the per-application topic.
  """

  alias Ecto.Multi
  alias Showcase.Common.AuditLog
  alias Showcase.RecruitFlow.Impl.StateMachine
  alias Showcase.RecruitFlow.Schemas.Application
  alias Showcase.Repo

  @spec apply(integer(), String.t(), keyword()) ::
          {:ok, Application.t()} | {:error, :invalid_transition | term()}
  def apply(application_id, to_state, opts) do
    actor = Keyword.fetch!(opts, :actor)
    reason = Keyword.get(opts, :reason, "")
    transcript = Keyword.get(opts, :transcript)
    eval = Keyword.get(opts, :eval)

    multi =
      Multi.new()
      |> Multi.run(:load, fn _repo, _ ->
        case Repo.get(Application, application_id) do
          nil -> {:error, :not_found}
          app -> {:ok, app}
        end
      end)
      |> Multi.run(:check, fn _repo, %{load: app} ->
        if StateMachine.allowed?(app.state, to_state) do
          {:ok, app}
        else
          {:error, :invalid_transition}
        end
      end)
      |> Multi.run(:update, fn _repo, %{load: app} ->
        attrs =
          %{state: to_state, state_changed_at: DateTime.utc_now()}
          |> maybe_put(:transcript, transcript)
          |> maybe_put(:eval, eval)

        app |> Application.changeset(attrs) |> Repo.update()
      end)

    case Repo.transaction(multi) do
      {:ok, %{load: app, update: updated}} ->
        {:ok, _} =
          AuditLog
          |> Ash.Changeset.for_create(:write, %{
            demo: "recruit_flow",
            entity_type: "application",
            entity_id: to_string(app.id),
            event: "state_change",
            payload: %{from: app.state, to: to_state, reason: reason},
            actor: actor
          })
          |> Ash.create()

        Phoenix.PubSub.broadcast(
          Showcase.PubSub,
          "recruit_flow:applications:#{app.id}",
          {:recruit_flow, :transitioned,
           %{application_id: app.id, from: app.state, to: to_state}}
        )

        {:ok, updated}

      {:error, :check, :invalid_transition, _} ->
        {:error, :invalid_transition}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
