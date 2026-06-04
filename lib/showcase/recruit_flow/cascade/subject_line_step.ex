defmodule Showcase.RecruitFlow.Cascade.SubjectLineStep do
  @behaviour Showcase.Common.CascadeMatcher.Step

  alias Showcase.RecruitFlow.Schemas.Application

  @impl true
  def name, do: :subject_line

  @impl true
  def try_match(%{subject_line: subj}, %{repo: repo}) when is_binary(subj) and subj != "" do
    case Regex.run(~r/Application #C-(\d+)/i, subj) do
      [_, id_string] ->
        with {id, ""} <- Integer.parse(id_string),
             %Application{state: "QUALIFIED"} = app <- repo.get(Application, id) do
          {:match, app.id, 1.0}
        else
          _ -> :no_match
        end

      _ ->
        :no_match
    end
  end

  def try_match(_, _), do: :no_match
end
