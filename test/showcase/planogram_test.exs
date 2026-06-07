defmodule Showcase.PlanogramTest do
  @moduledoc """
  Upload helpers added in Phase 8 — covers `create_planogram_with_reference/2`
  and `save_shelf_photo/2`.
  """
  use Showcase.DataCase, async: false

  alias Showcase.Planogram.{MobileHandoff, VerificationTask}

  @refs_dir "priv/static/images/planogram/refs"

  setup do
    File.rm_rf!(@refs_dir)
    File.mkdir_p!(@refs_dir)
    File.rm_rf!("priv/static/uploads/planogram")
    File.mkdir_p!("priv/static/uploads/planogram")
    :ok
  end

  describe "create_planogram_with_reference/2" do
    test "writes image bytes to refs dir and inserts a planogram row" do
      bytes = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0>>

      attrs = %{
        "name" => "Upload Test PG #{System.unique_integer([:positive])}",
        "description" => "from upload helper",
        "expected_rows" => %{"rows" => []}
      }

      assert {:ok, pg} = Showcase.Planogram.create_planogram_with_reference(attrs, bytes)
      assert pg.reference_image_path =~ "/images/planogram/refs/"
      assert pg.reference_image_path =~ ".png"

      on_disk = File.read!(Path.join("priv/static", pg.reference_image_path))
      assert on_disk == bytes
    end

    test "detects JPEG bytes and uses a .jpg extension" do
      bytes = <<0xFF, 0xD8, 0xFF, 0xE0, 0, 0>>

      attrs = %{"name" => "JPEG PG #{System.unique_integer([:positive])}"}

      assert {:ok, pg} = Showcase.Planogram.create_planogram_with_reference(attrs, bytes)
      assert pg.reference_image_path =~ ".jpg"
    end

    test "supports atom-keyed attrs" do
      bytes = <<137, 80, 78, 71, 13, 10, 26, 10>>

      attrs = %{
        name: "Atom-key PG #{System.unique_integer([:positive])}",
        description: "ok"
      }

      assert {:ok, _pg} = Showcase.Planogram.create_planogram_with_reference(attrs, bytes)
    end
  end

  describe "save_shelf_photo/2" do
    test "delegates to MobileHandoff.finalize_upload/2" do
      task = insert_task()
      bytes = <<137, 80, 78, 71, 13, 10, 26, 10>>

      assert {:ok, updated} = Showcase.Planogram.save_shelf_photo(task, bytes)
      assert updated.photo_path =~ "/uploads/planogram/"

      on_disk = File.read!(Path.join("priv/static", updated.photo_path))
      assert on_disk == bytes
    end
  end

  defp insert_task do
    {:ok, pg} =
      Showcase.Repo.insert(%Showcase.Planogram.Planogram{
        name: "TaskHelper PG #{System.unique_integer([:positive])}",
        reference_image_path: "/images/planogram/whatever.png",
        expected_rows: %{"rows" => []}
      })

    {:ok, task} =
      Showcase.Repo.insert(%VerificationTask{
        planogram_id: pg.id,
        store_name: "Shelf Test",
        due_date: Date.utc_today(),
        mobile_token: MobileHandoff.generate_token(),
        scenario: "compliant",
        status: "pending"
      })

    task
  end
end
