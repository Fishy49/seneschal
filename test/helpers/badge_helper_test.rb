require "test_helper"

class BadgeHelperTest < ActionView::TestCase
  test "status_badge renders span with status text" do
    html = status_badge("running")
    assert_includes html, "running"
    assert_includes html, "bg-accent/15"
  end

  test "status_badge adds pulse dot for running" do
    html = status_badge("running")
    assert_includes html, "animate-pulse"
  end

  test "status_badge adds pulse dot for retrying" do
    html = status_badge("retrying")
    assert_includes html, "animate-pulse"
  end

  test "status_badge no pulse for completed" do
    html = status_badge("completed")
    assert_not_includes html, "animate-pulse"
  end

  test "status_badge uses pending style for unknown status" do
    html = status_badge("unknown")
    assert_includes html, STATUS_CLASSES["pending"]
  end

  test "status_badge carries a plain-language tooltip" do
    assert_includes status_badge("awaiting_approval"), "Paused until a person approves this step"
    assert_includes status_badge("running"), "Working on it now"
  end

  test "status_badge omits the tooltip for an unknown status" do
    assert_not_includes status_badge("unknown"), "title="
  end

  test "type_badge carries a plain-language tooltip" do
    assert_includes type_badge("ci_check"), "Waits for GitHub checks"
  end

  test "type_badge renders span with type text" do
    html = type_badge("skill")
    assert_includes html, "skill"
    assert_includes html, "bg-accent/15"
  end
end
