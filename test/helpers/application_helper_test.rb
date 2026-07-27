require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
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

  test "workflow_stats_line is nil for a workflow nobody has run" do
    assert_nil workflow_stats_line(Workflow::Stats.new(run_count: 0, success_rate: nil, median_cost: nil))
  end

  test "workflow_stats_line joins the parts it has" do
    line = workflow_stats_line(Workflow::Stats.new(run_count: 34, success_rate: 0.906, median_cost: 1.2))
    assert_equal "34 runs · 91% succeeded · ~$1.20", line
  end

  test "workflow_stats_line drops parts with no honest number" do
    assert_equal "1 run", workflow_stats_line(Workflow::Stats.new(run_count: 1, success_rate: nil, median_cost: nil))
    assert_equal "2 runs · 0% succeeded",
                 workflow_stats_line(Workflow::Stats.new(run_count: 2, success_rate: 0.0, median_cost: 0.0))
  end

  test "run_display_name names a run after its task" do
    assert_equal "Add search \u00b7 run 1", run_display_name(runs(:completed_run))
  end

  test "run_display_name falls back to the id without a task" do
    run = runs(:failed_run)
    assert_equal "Manual run ##{run.id}", run_display_name(run)
  end
end
