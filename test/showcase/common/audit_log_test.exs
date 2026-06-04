defmodule Showcase.Common.AuditLogTest do
  use Showcase.DataCase, async: true

  alias Showcase.Common.AuditLog

  test "write + read for_entity" do
    {:ok, _} =
      AuditLog
      |> Ash.Changeset.for_create(:write, %{
        demo: "recruit_flow",
        entity_type: "application",
        entity_id: "42",
        event: "transitioned",
        payload: %{from: "pending", to: "qualified"},
        actor: "system"
      })
      |> Ash.create()

    {:ok, [entry]} = AuditLog.for_entity("recruit_flow", "application", "42")
    assert entry.event == "transitioned"
    assert entry.payload == %{"from" => "pending", "to" => "qualified"}
  end
end
