defmodule Showcase.Common.SystemPromptSeederTest do
  use Showcase.DataCase, async: false

  alias Showcase.Common.{SystemPrompt, SystemPromptSeeder}

  describe "upsert/3" do
    test "creates a new row on first call" do
      :ok = SystemPromptSeeder.upsert("test_demo", "section_a", "You are a test prompt.")

      {:ok, [row]} = SystemPrompt.latest("test_demo", "section_a")
      assert row.body == "You are a test prompt."
      assert row.version == 1
    end

    test "is idempotent — same body → no new version" do
      :ok = SystemPromptSeeder.upsert("test_demo", "section_b", "Identical body.")
      :ok = SystemPromptSeeder.upsert("test_demo", "section_b", "Identical body.")

      rows =
        Showcase.Common.SystemPrompt
        |> Ash.read!()
        |> Enum.filter(&(&1.demo == "test_demo" and &1.section == "section_b"))

      assert length(rows) == 1
    end

    test "new body → new version" do
      :ok = SystemPromptSeeder.upsert("test_demo", "section_c", "Version 1 body.")
      :ok = SystemPromptSeeder.upsert("test_demo", "section_c", "Version 2 body.")

      rows =
        Showcase.Common.SystemPrompt
        |> Ash.read!()
        |> Enum.filter(&(&1.demo == "test_demo" and &1.section == "section_c"))

      assert length(rows) == 2

      {:ok, [latest]} = SystemPrompt.latest("test_demo", "section_c")
      assert latest.version == 2
      assert latest.body == "Version 2 body."
    end
  end
end
