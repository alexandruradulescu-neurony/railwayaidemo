defmodule Showcase.OrderFlow.WorkerTest do
  use Showcase.DataCase, async: false
  use Oban.Testing, repo: Showcase.Repo

  alias Showcase.Common.AnthropicClient.Mock
  alias Showcase.OrderFlow.Schemas.{Client, Product, SyntheticMessage}
  alias Showcase.OrderFlow.Worker
  alias Showcase.Repo

  setup do
    Mock.reset()
    {:ok, _} = Repo.insert(%Client{name: "Acme Inc"})

    {:ok, _} =
      %Product{}
      |> Product.changeset(%{sku: "WGT-001", name: "Widget", normalized_name: "widget"})
      |> Repo.insert()

    {:ok, msg} =
      %SyntheticMessage{}
      |> SyntheticMessage.changeset(%{
        body: "1 widget please",
        kind: "email",
        scenario: "one_widget",
        client_hint: "Acme Inc"
      })
      |> Repo.insert()

    Mock.register(
      "order_flow:extract:v1",
      scenario: "one_widget",
      text: ~s({"client_hint": "Acme Inc", "lines": [{"description": "widget", "quantity": 1}]})
    )

    {:ok, %{message: msg}}
  end

  test "perform/1 processes the message and returns :ok", %{message: msg} do
    assert :ok = perform_job(Worker, %{"message_id" => msg.id})
  end

  test "perform/1 returns {:error, _} for an unknown message id" do
    assert {:error, :not_found} = perform_job(Worker, %{"message_id" => 999_999})
  end

  test "Worker is configured on :order_flow queue" do
    assert Worker.__opts__()[:queue] == :order_flow
  end
end
