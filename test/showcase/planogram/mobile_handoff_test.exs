defmodule Showcase.Planogram.MobileHandoffTest do
  use Showcase.DataCase, async: false

  alias Showcase.Planogram.{Planogram, VerificationTask, MobileHandoff}
  alias Showcase.Repo

  setup do
    File.rm_rf!("priv/static/uploads/planogram")
    File.mkdir_p!("priv/static/uploads/planogram")
    :ok
  end

  describe "generate_token/0" do
    test "produces unique URL-safe tokens" do
      t1 = MobileHandoff.generate_token()
      t2 = MobileHandoff.generate_token()

      refute t1 == t2
      assert byte_size(t1) >= 16
      assert t1 == URI.encode(t1)
    end
  end

  describe "find_task_by_token/1" do
    test "finds an open task by mobile_token" do
      task = insert_task(status: "pending")
      assert {:ok, found} = MobileHandoff.find_task_by_token(task.mobile_token)
      assert found.id == task.id
    end

    test "returns :not_found for unknown token" do
      assert {:error, :not_found} = MobileHandoff.find_task_by_token("nope-#{System.unique_integer()}")
    end

    test "refuses tokens for tasks already complete or failed" do
      task = insert_task(status: "complete")
      assert {:error, :already_processed} = MobileHandoff.find_task_by_token(task.mobile_token)
    end
  end

  describe "finalize_upload/2" do
    test "writes photo bytes to priv/static/uploads/planogram and updates task.photo_path" do
      task = insert_task(status: "pending")
      bytes = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0>>

      assert {:ok, updated} = MobileHandoff.finalize_upload(task, bytes)
      assert updated.photo_path =~ "/uploads/planogram/"
      assert updated.photo_path =~ ".png"

      on_disk = File.read!(Path.join("priv/static", updated.photo_path))
      assert on_disk == bytes
    end
  end

  defp insert_task(opts) do
    {:ok, pg} = Repo.insert(%Planogram{
      name: "handoff-pg-#{System.unique_integer([:positive])}",
      reference_image_path: "/images/planogram/reference.png",
      expected_rows: %{"rows" => []}
    })

    {:ok, task} = Repo.insert(%VerificationTask{
      planogram_id: pg.id,
      store_name: "Handoff Test",
      due_date: Date.utc_today(),
      mobile_token: MobileHandoff.generate_token(),
      scenario: "compliant",
      status: Keyword.get(opts, :status, "pending")
    })

    task
  end
end
