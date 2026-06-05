defmodule Showcase.Planogram.VisionPipelineTest do
  use Showcase.DataCase, async: false

  alias Showcase.Planogram
  alias Showcase.Planogram.{Planogram, VerificationTask, VisionPipeline, MockPrompts}
  alias Showcase.Repo

  setup do
    MockPrompts.register_all()
    Phoenix.PubSub.subscribe(Showcase.PubSub, "planogram:task:*")
    :ok
  end

  describe "analyze/2" do
    test "compliant scenario: task transitions pending → analyzing → complete; result + usage persisted" do
      task = build_task("compliant")

      assert {:ok, updated} = VisionPipeline.analyze(task, photo_bytes: png_bytes())

      assert updated.status == "complete"
      assert updated.result["compliance_score"] >= 90
      assert updated.usage["input_tokens"] > 0
      assert updated.usage["cost_estimate_cents"] > 0
    end

    test "minor_issues scenario persists rich JSON" do
      task = build_task("minor_issues")
      {:ok, updated} = VisionPipeline.analyze(task, photo_bytes: png_bytes())

      assert updated.result["compliance_score"] >= 60 and updated.result["compliance_score"] < 90
      assert length(updated.result["issues"]) >= 1
    end

    test "missing photo file → task marked failed with error_reason" do
      task = build_task("compliant")

      assert {:error, _} = VisionPipeline.analyze(task, photo_bytes: nil)

      reloaded = Repo.get(VerificationTask, task.id)
      assert reloaded.status == "failed"
      assert reloaded.error_reason =~ "no photo"
    end

    test "truncated mock JSON salvages via ResilientJSONParser and stays :complete with partial flag" do
      # Register a deliberately truncated response under a custom scenario
      Showcase.Common.AnthropicClient.Mock.register(
        Showcase.Planogram.Impl.VisionRequest.fingerprint(),
        scenario: "truncated",
        text: ~s|{"compliance_score": 75, "rows": [{"name": "Top", "po|,
        stop_reason: "max_tokens",
        input_tokens: 2000,
        output_tokens: 200
      )

      task = build_task("truncated")
      {:ok, updated} = VisionPipeline.analyze(task, photo_bytes: png_bytes(), max_tokens: 200)

      assert updated.status == "complete"
      assert updated.result["compliance_score"] == 75
      assert updated.result["_partial"] == true
    end
  end

  defp build_task(scenario) do
    {:ok, planogram} =
      Repo.insert(%Planogram{
        name: "test-planogram-#{System.unique_integer([:positive])}",
        reference_image_path: "/images/planogram/reference.png",
        expected_rows: %{
          "rows" => [
            %{"name" => "Top", "position" => 1,
              "products" => [%{"sku" => "S1", "name" => "Coke", "qty" => 6}]}
          ]
        }
      })

    {:ok, task} =
      Repo.insert(%VerificationTask{
        planogram_id: planogram.id,
        store_name: "Test Store",
        due_date: Date.utc_today(),
        mobile_token: random_token(),
        scenario: scenario,
        status: "pending",
        photo_path: "/uploads/planogram/test.png"
      })

    Map.put(task, :planogram, planogram)
  end

  defp png_bytes, do: <<137, 80, 78, 71, 13, 10, 26, 10>>
  defp random_token, do: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
end
