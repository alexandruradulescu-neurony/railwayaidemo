defmodule Showcase.Planogram.Impl.OverdueTest do
  use ExUnit.Case, async: true

  alias Showcase.Planogram.Impl.Overdue
  alias Showcase.Planogram.VerificationTask

  describe "overdue?/2" do
    test "false when due_date is today" do
      task = %VerificationTask{due_date: ~D[2026-06-04], status: "pending"}
      refute Overdue.overdue?(task, ~D[2026-06-04])
    end

    test "false when due_date is tomorrow" do
      task = %VerificationTask{due_date: ~D[2026-06-05], status: "pending"}
      refute Overdue.overdue?(task, ~D[2026-06-04])
    end

    test "true when due_date is yesterday and status is pending" do
      task = %VerificationTask{due_date: ~D[2026-06-03], status: "pending"}
      assert Overdue.overdue?(task, ~D[2026-06-04])
    end

    test "true when due_date is in the past and status is analyzing" do
      task = %VerificationTask{due_date: ~D[2026-06-01], status: "analyzing"}
      assert Overdue.overdue?(task, ~D[2026-06-04])
    end

    test "false when status is complete regardless of due_date" do
      task = %VerificationTask{due_date: ~D[2026-06-01], status: "complete"}
      refute Overdue.overdue?(task, ~D[2026-06-04])
    end

    test "false when status is failed regardless of due_date" do
      task = %VerificationTask{due_date: ~D[2026-06-01], status: "failed"}
      refute Overdue.overdue?(task, ~D[2026-06-04])
    end
  end

  describe "bucket/2" do
    test "groups by today / tomorrow / overdue / later" do
      tasks = [
        %VerificationTask{id: 1, due_date: ~D[2026-06-04], status: "pending"},
        %VerificationTask{id: 2, due_date: ~D[2026-06-05], status: "pending"},
        %VerificationTask{id: 3, due_date: ~D[2026-06-03], status: "pending"},
        %VerificationTask{id: 4, due_date: ~D[2026-06-10], status: "pending"},
        %VerificationTask{id: 5, due_date: ~D[2026-06-01], status: "complete"}
      ]

      buckets = Overdue.bucket(tasks, ~D[2026-06-04])
      assert Enum.map(buckets.overdue, & &1.id) == [3]
      assert Enum.map(buckets.today, & &1.id) == [1]
      assert Enum.map(buckets.tomorrow, & &1.id) == [2]
      assert Enum.map(buckets.later, & &1.id) == [4]
      assert Enum.map(buckets.done, & &1.id) == [5]
    end
  end
end
