defmodule Showcase.RecruitFlow.Cascade.PdfContentStep do
  @behaviour Showcase.Common.CascadeMatcher.Step

  import Ecto.Query

  alias Showcase.Common.AnthropicClient
  alias Showcase.Common.AnthropicClient.Types.Request
  alias Showcase.Common.Config
  alias Showcase.Common.ResilientJSONParser
  alias Showcase.RecruitFlow.Schemas.{Application, Candidate}

  @fingerprint "recruit_flow:cv_match:v1"

  @impl true
  def name, do: :pdf_content

  @impl true
  def try_match(%{pdf_text: pdf}, %{repo: repo}) when is_binary(pdf) and pdf != "" do
    req = %Request{
      model: Config.default_model(),
      messages: [%{role: "user", content: pdf}],
      system: ~s|Extract the candidate's full name from the CV content. Respond with JSON: {"candidate_name": "...", "confidence": 0.0-1.0}.|,
      metadata: %{fingerprint: @fingerprint, scenario: pdf}
    }

    with {:ok, response} <- AnthropicClient.call(req),
         {:ok, %{"candidate_name" => name, "confidence" => conf}, _} <-
           ResilientJSONParser.parse(response.text),
         %Application{} = app <-
           repo.one(
             from a in Application,
               join: c in Candidate, on: c.id == a.candidate_id,
               where: c.name == ^name and a.state == "QUALIFIED",
               limit: 1
           ) do
      {:match, app.id, conf}
    else
      _ -> :no_match
    end
  end

  def try_match(_, _), do: :no_match
end
