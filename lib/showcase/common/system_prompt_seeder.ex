defmodule Showcase.Common.SystemPromptSeeder do
  @moduledoc """
  Idempotent upsert helper for `Showcase.Common.SystemPrompt` rows.

  Used by each demo's seed to record the active system prompt as reference
  data — the admin viewer reads from these rows. Pipelines still use their
  inline string for now; this seeder makes the prompts *visible* in the
  admin without forcing a refactor of every pipeline.

  Semantics:
    * No prior row for `(demo, section)` → creates v1.
    * Latest row's body matches → no-op.
    * Latest row's body differs → creates v+1.
  """

  alias Showcase.Common.SystemPrompt

  @spec upsert(String.t(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def upsert(demo, section, body, opts \\ []) do
    note = Keyword.get(opts, :note)
    # Normalize trailing whitespace — Postgres/Ash sometimes strip trailing
    # newlines on store, which would cause spurious version bumps on re-seed.
    normalized = normalize(body)

    case SystemPrompt.latest(demo, section) do
      {:ok, [latest]} ->
        if normalize(latest.body) == normalized do
          :ok
        else
          create_new_version(demo, section, latest.version + 1, normalized, note)
        end

      {:ok, []} ->
        create_new_version(demo, section, 1, normalized, note)

      {:error, _} = err ->
        err
    end
  end

  defp normalize(body) when is_binary(body), do: String.trim_trailing(body)

  defp create_new_version(demo, section, version, body, note) do
    SystemPrompt
    |> Ash.Changeset.for_create(:create, %{
      demo: demo,
      section: section,
      version: version,
      body: body,
      note: note
    })
    |> Ash.create!()

    :ok
  end
end
