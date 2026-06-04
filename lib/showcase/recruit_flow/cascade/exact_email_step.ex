defmodule Showcase.RecruitFlow.Cascade.ExactEmailStep do
  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.RecruitFlow.Schemas.{Application, Candidate}

  @impl true
  def name, do: :exact_email

  @impl true
  def try_match(%{email: email}, %{repo: repo}) when is_binary(email) and email != "" do
    case repo.one(
           from a in Application,
             join: c in Candidate, on: c.id == a.candidate_id,
             where: c.email == ^email and a.state == "QUALIFIED",
             select: a.id,
             limit: 1
         ) do
      nil -> :no_match
      id -> {:match, id, 1.0}
    end
  end

  def try_match(_, _), do: :no_match
end
