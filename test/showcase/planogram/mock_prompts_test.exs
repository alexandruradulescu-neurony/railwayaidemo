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

  defp call(scenario) do
    req = %Request{
      model: "claude-sonnet-4-5",
      messages: [%{role: "user", content: []}],
      metadata: %{fingerprint: "planogram_vision_v1", scenario: scenario}
    }

    {:ok, resp} = AnthropicClient.call(req)
    Jason.decode!(resp.text)
  end

  describe "register_all/0" do
    test "registers compliant, minor_issues, major_issues scenarios" do
      for scenario <- ["compliant", "minor_issues", "major_issues"] do
        parsed = call(scenario)
        assert is_integer(parsed["compliance_score"])
        assert is_list(parsed["extracted_prices"])
        assert is_list(parsed["issues"])
      end
    end

    test "compliant: score >= 90, no issues, prices extracted" do
      parsed = call("compliant")
      assert parsed["compliance_score"] >= 90
      assert parsed["issues"] == []
      assert length(parsed["extracted_prices"]) >= 4
    end

    test "minor_issues: score 60-89, ≥1 issue with row+position, prices extracted" do
      parsed = call("minor_issues")
      assert parsed["compliance_score"] >= 60 and parsed["compliance_score"] < 90
      assert length(parsed["issues"]) >= 1

      # Each issue carries positioning hints for the UI overlay
      Enum.each(parsed["issues"], fn issue ->
        assert is_integer(issue["row"]) or is_nil(issue["row"])
        assert issue["horizontal_position"] in ["left", "center", "right", nil]
      end)

      # extracted_prices look like RON tags
      assert Enum.any?(parsed["extracted_prices"], &String.contains?(&1["text"], "RON"))
    end

    test "major_issues: score < 50, ≥1 high-severity, ≥1 out_of_stock" do
      parsed = call("major_issues")
      assert parsed["compliance_score"] < 50
      assert Enum.any?(parsed["issues"], &(&1["severity"] == "high"))
      assert Enum.any?(parsed["issues"], &(&1["type"] == "out_of_stock"))
    end
  end
end
