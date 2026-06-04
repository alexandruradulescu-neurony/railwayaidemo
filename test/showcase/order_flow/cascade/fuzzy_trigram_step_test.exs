defmodule Showcase.OrderFlow.Cascade.FuzzyTrigramStepTest do
  use Showcase.DataCase, async: false

  alias Showcase.OrderFlow.Cascade.FuzzyTrigramStep
  alias Showcase.OrderFlow.Schemas.Product
  alias Showcase.Repo

  setup do
    {:ok, hinges} =
      %Product{}
      |> Product.changeset(%{sku: "HNG-001", name: "Hinges", normalized_name: "hinges"})
      |> Repo.insert()

    {:ok, %{hinges: hinges}}
  end

  defp ctx, do: %{repo: Repo, now: DateTime.utc_now(), client_id: 1}

  test "near-spelling match returns product with similarity >= 0.5", %{hinges: hinges} do
    # NOTE: pg_trgm trigram similarity is sensitive to length; "hings" vs "hinges"
    # scores ~0.44 (below threshold), so we use "hingez" (one-char swap), which
    # scores ~0.56 — clearly a near-spelling, above threshold, below exact.
    {:match, found, score} = FuzzyTrigramStep.try_match("hingez", ctx())
    assert found.id == hinges.id
    assert score >= 0.5
    assert score < 1.0
  end

  test "exact match returns score 1.0", %{hinges: hinges} do
    {:match, found, score} = FuzzyTrigramStep.try_match("hinges", ctx())
    assert found.id == hinges.id
    assert score == 1.0
  end

  test "completely unrelated input returns no_match" do
    assert FuzzyTrigramStep.try_match("zzzzzzz", ctx()) == :no_match
  end

  test "name/0 returns :fuzzy_trigram" do
    assert FuzzyTrigramStep.name() == :fuzzy_trigram
  end
end
