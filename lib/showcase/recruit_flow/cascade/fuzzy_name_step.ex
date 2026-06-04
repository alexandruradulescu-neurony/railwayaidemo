defmodule Showcase.RecruitFlow.Cascade.FuzzyNameStep do
  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.RecruitFlow.Schemas.{Application, Candidate}

  @similarity_threshold 0.6

  @impl true
  def name, do: :fuzzy_name

  @impl true
  def try_match(%{pdf_text: pdf}, %{repo: repo}) when is_binary(pdf) and pdf != "" do
    name_guess =
      case Regex.run(~r/([A-Z][a-z]+ [A-Z][a-z]+)/, pdf) do
        [_, n] -> n
        _ -> nil
      end

    case name_guess do
      nil ->
        :no_match

      guess ->
        query =
          from a in Application,
            join: c in Candidate, on: c.id == a.candidate_id,
            where: a.state == "QUALIFIED",
            select: {a.id, c.name, fragment("similarity(?, ?)", c.name, ^guess)},
            order_by: [desc: fragment("similarity(?, ?)", c.name, ^guess)],
            limit: 1

        case repo.one(query) do
          {id, _name, score} when score >= @similarity_threshold -> {:match, id, score}
          _ -> :no_match
        end
    end
  end

  def try_match(_, _), do: :no_match
end
