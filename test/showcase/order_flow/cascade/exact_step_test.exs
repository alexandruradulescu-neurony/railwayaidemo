defmodule Showcase.OrderFlow.Cascade.ExactStepTest do
  use Showcase.DataCase, async: true

  alias Showcase.OrderFlow.Cascade.ExactStep
  alias Showcase.OrderFlow.Schemas.Product
  alias Showcase.Repo

  setup do
    {:ok, widget} =
      %Product{}
      |> Product.changeset(%{sku: "WGT-001", name: "Widget", normalized_name: "widget"})
      |> Repo.insert()

    {:ok, %{widget: widget}}
  end

  defp ctx, do: %{repo: Repo, now: DateTime.utc_now(), client_id: 1}

  test "returns 1.0 match when normalized input equals product normalized_name", %{widget: widget} do
    assert {:match, found, 1.0} = ExactStep.try_match("Widget", ctx())
    assert found.id == widget.id
  end

  test "matches after Normalize trims and lowercases", %{widget: widget} do
    assert {:match, found, 1.0} = ExactStep.try_match("  WIDGET  ", ctx())
    assert found.id == widget.id
  end

  test "no_match when product doesn't exist" do
    assert ExactStep.try_match("nonexistent", ctx()) == :no_match
  end

  test "name/0 returns :exact" do
    assert ExactStep.name() == :exact
  end
end
