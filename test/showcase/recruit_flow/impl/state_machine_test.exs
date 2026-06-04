defmodule Showcase.RecruitFlow.Impl.StateMachineTest do
  use ExUnit.Case, async: true

  alias Showcase.RecruitFlow.Impl.StateMachine

  describe "states/0" do
    test "returns exactly 5 states" do
      assert length(StateMachine.states()) == 5
    end

    test "includes PENDING, QUALIFIED, HIRED, REJECTED, NEEDS_HUMAN" do
      states = StateMachine.states()
      assert "PENDING" in states
      assert "QUALIFIED" in states
      assert "HIRED" in states
      assert "REJECTED" in states
      assert "NEEDS_HUMAN" in states
    end
  end

  describe "allowed?/2" do
    test "PENDING → QUALIFIED is allowed" do
      assert StateMachine.allowed?("PENDING", "QUALIFIED")
    end

    test "PENDING → REJECTED is allowed" do
      assert StateMachine.allowed?("PENDING", "REJECTED")
    end

    test "PENDING → NEEDS_HUMAN is allowed" do
      assert StateMachine.allowed?("PENDING", "NEEDS_HUMAN")
    end

    test "PENDING → PENDING is allowed (callback re-queue)" do
      assert StateMachine.allowed?("PENDING", "PENDING")
    end

    test "PENDING → HIRED is not allowed (must go through QUALIFIED)" do
      refute StateMachine.allowed?("PENDING", "HIRED")
    end

    test "QUALIFIED → HIRED is allowed" do
      assert StateMachine.allowed?("QUALIFIED", "HIRED")
    end

    test "QUALIFIED → REJECTED is allowed (auto-close stale)" do
      assert StateMachine.allowed?("QUALIFIED", "REJECTED")
    end

    test "terminal states have no outgoing" do
      refute StateMachine.allowed?("HIRED", "PENDING")
      refute StateMachine.allowed?("REJECTED", "PENDING")
      refute StateMachine.allowed?("NEEDS_HUMAN", "QUALIFIED")
    end

    test "unknown state returns false" do
      refute StateMachine.allowed?("MADE_UP", "PENDING")
      refute StateMachine.allowed?("PENDING", "MADE_UP")
    end
  end

  describe "terminal?/1" do
    test "true for HIRED, REJECTED, NEEDS_HUMAN" do
      assert StateMachine.terminal?("HIRED")
      assert StateMachine.terminal?("REJECTED")
      assert StateMachine.terminal?("NEEDS_HUMAN")
    end

    test "false for PENDING, QUALIFIED" do
      refute StateMachine.terminal?("PENDING")
      refute StateMachine.terminal?("QUALIFIED")
    end
  end

  describe "next/1" do
    test "PENDING has 4 next options (incl. self-loop)" do
      assert length(StateMachine.next("PENDING")) == 4
    end

    test "HIRED has no next" do
      assert StateMachine.next("HIRED") == []
    end
  end
end
