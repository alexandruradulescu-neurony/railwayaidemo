defmodule Showcase.Planogram.WorkerTest do
  use Showcase.DataCase, async: false
  use Oban.Testing, repo: Showcase.Repo

  alias Showcase.Planogram.{Planogram, VerificationTask, Worker, MockPrompts}
  alias Showcase.Repo

  setup do
    MockPrompts.register_all()
    :ok
  end

  describe "perform/1" do
    test "loads task, reads bundled photo from priv/static, runs VisionPipeline, marks complete" do
      {:ok, planogram} =
        Repo.insert(%Planogram{
          name: "worker-pg-#{System.unique_integer([:positive])}",
          reference_image_path: "/images/planogram/reference.png",
          expected_rows: %{"rows" => []}
        })

      {:ok, task} =
        Repo.insert(%VerificationTask{
          planogram_id: planogram.id,
          store_name: "Worker Test",
          due_date: Date.utc_today(),
          mobile_token: "wt-#{System.unique_integer([:positive])}",
          scenario: "compliant",
          status: "pending",
          # Worker reads bundled photo by scenario when photo_path is nil
          photo_path: nil
        })

      assert :ok = perform_job(Worker, %{"task_id" => task.id})

      reloaded = Repo.get(VerificationTask, task.id)
      assert reloaded.status == "complete"
      assert reloaded.result["compliance_score"] >= 90
    end

    test "honors :max_tokens override in args (used by force-truncation demo)" do
      Showcase.Common.AnthropicClient.Mock.register(
        Showcase.Planogram.Impl.VisionRequest.fingerprint(),
        scenario: "compliant",
        text: ~s|{"compliance_score": 80, "rows": [{"name": "Top|,
        stop_reason: "max_tokens",
        input_tokens: 100,
        output_tokens: 50
      )

      {:ok, planogram} = Repo.insert(%Planogram{
        name: "max-tokens-pg",
        reference_image_path: "/images/planogram/reference.png",
        expected_rows: %{"rows" => []}
      })

      {:ok, task} = Repo.insert(%VerificationTask{
        planogram_id: planogram.id,
        store_name: "Truncation Test",
        due_date: Date.utc_today(),
        mobile_token: "trunc-#{System.unique_integer([:positive])}",
        scenario: "compliant",
        photo_path: nil
      })

      assert :ok = perform_job(Worker, %{"task_id" => task.id, "max_tokens" => 200})

      reloaded = Repo.get(VerificationTask, task.id)
      assert reloaded.status == "complete"
      assert reloaded.result["_partial"] == true
    end
  end
end
