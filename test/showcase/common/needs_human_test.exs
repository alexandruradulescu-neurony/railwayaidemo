defmodule Showcase.Common.NeedsHumanTest do
  use ExUnit.Case, async: true

  alias Showcase.Common.NeedsHuman
  alias Showcase.Common.NeedsHuman.Decision

  test "ok/0 returns a no-review decision" do
    assert %Decision{needs_review?: false, reasons: []} = NeedsHuman.ok()
  end

  test "escalate/2 returns a review-required decision" do
    assert %Decision{needs_review?: true, reasons: ["why"]} = NeedsHuman.escalate(["why"])
  end

  test "from_confidence escalates below threshold" do
    assert %Decision{needs_review?: true, source: :test} =
             NeedsHuman.from_confidence(0.5, 0.7, :test)
  end

  test "from_confidence does not escalate at or above threshold" do
    assert %Decision{needs_review?: false} = NeedsHuman.from_confidence(0.8, 0.7, :test)
  end
end
