defmodule Showcase.OrderFlow.ClientResolverTest do
  use Showcase.DataCase, async: true

  alias Showcase.OrderFlow.ClientResolver
  alias Showcase.OrderFlow.Schemas.Client
  alias Showcase.Repo

  setup do
    {:ok, acme} = Repo.insert(%Client{name: "Acme Inc", email: "acme@example.com"})
    {:ok, %{acme: acme}}
  end

  test "exact name match returns client", %{acme: acme} do
    assert {:ok, found} = ClientResolver.resolve("Acme Inc", Repo)
    assert found.id == acme.id
  end

  test "case-insensitive name match" do
    assert {:ok, _} = ClientResolver.resolve("acme inc", Repo)
  end

  test "no match returns needs_human" do
    assert {:needs_human, _reason} = ClientResolver.resolve("Unknown Co", Repo)
  end

  test "nil hint returns needs_human" do
    assert {:needs_human, _reason} = ClientResolver.resolve(nil, Repo)
  end
end
