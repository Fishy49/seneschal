require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
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

  test "type_badge renders span with type text" do
    html = type_badge("skill")
    assert_includes html, "skill"
    assert_includes html, "bg-accent/15"
  end

  test "format_duration formats seconds" do
    assert_equal "5.2s", format_duration(5.23)
  end

  test "format_duration formats minutes" do
    assert_equal "2m 30s", format_duration(150)
  end

  test "format_duration formats hours" do
    assert_equal "1h 30m", format_duration(5400)
  end

  test "format_duration returns dash for nil" do
    assert_equal "\u2014", format_duration(nil)
  end

  test "format_cost formats small amounts with 4 decimals" do
    assert_equal "$0.0052", format_cost(0.0052)
  end

  test "format_cost formats larger amounts with 2 decimals" do
    assert_equal "$1.50", format_cost(1.50)
  end

  test "format_cost returns nil for nil" do
    assert_nil format_cost(nil)
  end

  test "format_tokens formats thousands" do
    assert_equal "15.0k", format_tokens(15_000)
  end

  test "format_tokens formats millions" do
    assert_equal "1.5M", format_tokens(1_500_000)
  end

  test "format_tokens returns nil for nil" do
    assert_nil format_tokens(nil)
  end

  test "format_tokens returns nil for zero" do
    assert_nil format_tokens(0)
  end

  test "usage_stats_bar formats full stats" do
    stats = {
      cost_usd: 0.05, input_tokens: 10_000, output_tokens: 2000,
      cache_read_tokens: 1000, cache_creation_tokens: 500,
      duration_ms: 90_000, num_turns: 3
    }
    bar = usage_stats_bar(stats)
    assert_includes bar, "$0.05"
    assert_includes bar, "tokens"
    assert_includes bar, "3 turns"
    assert_includes bar, "1m 30s"
  end

  test "usage_stats_bar returns nil for nil" do
    assert_nil usage_stats_bar(nil)
  end
end
