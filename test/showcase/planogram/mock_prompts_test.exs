defmodule Showcase.Planogram.MockPromptsTest do
  use ExUnit.Case, async: false

  alias Showcase.Common.AnthropicClient
  alias Showcase.Common.AnthropicClient.Types.Request
  alias Showcase.Planogram.MockPrompts

  setup do
    Showcase.Common.AnthropicClient.Mock.reset()
    MockPrompts.register_all()
    :ok
  end

  describe "register_all/0" do
    test "registers compliant, minor_issues, major_issues scenarios" do
      for scenario <- ["compliant", "minor_issues", "major_issues"] do
        req = %Request{
          model: "claude-sonnet-4-5",
          messages: [%{"role" => "user", "content" => []}],
          metadata: %{fingerprint: "planogram_vision_v1", scenario: scenario}
        }

        assert {:ok, resp} = AnthropicClient.call(req)
        assert is_binary(resp.text)
        parsed = Jason.decode!(resp.text)
        assert is_integer(parsed["compliance_score"])
      end
    end

    test "compliant scenario returns score >= 90" do
      req = %Request{
        model: "claude-sonnet-4-5",
        messages: [],
        metadata: %{fingerprint: "planogram_vision_v1", scenario: "compliant"}
      }

      {:ok, resp} = AnthropicClient.call(req)
      parsed = Jason.decode!(resp.text)
      assert parsed["compliance_score"] >= 90
      assert parsed["issues"] == []
    end

    test "minor_issues scenario has 1-2 issues with medium severity" do
      req = %Request{
        model: "claude-sonnet-4-5",
        messages: [],
        metadata: %{fingerprint: "planogram_vision_v1", scenario: "minor_issues"}
      }

      {:ok, resp} = AnthropicClient.call(req)
      parsed = Jason.decode!(resp.text)
      assert parsed["compliance_score"] >= 60 and parsed["compliance_score"] < 90
      assert length(parsed["issues"]) >= 1
    end

    test "major_issues scenario has high-severity issues + score < 50" do
      req = %Request{
        model: "claude-sonnet-4-5",
        messages: [],
        metadata: %{fingerprint: "planogram_vision_v1", scenario: "major_issues"}
      }

      {:ok, resp} = AnthropicClient.call(req)
      parsed = Jason.decode!(resp.text)
      assert parsed["compliance_score"] < 50
      assert Enum.any?(parsed["issues"], &(&1["severity"] == "high"))
    end
  end
end
