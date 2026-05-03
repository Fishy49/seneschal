require "test_helper"

class RunTest < ActiveSupport::TestCase
  test "valid run" do
    r = Run.new(workflow: workflows(:deploy), status: "pending")
    assert r.valid?
  end

  test "validates status inclusion" do
    r = Run.new(workflow: workflows(:deploy), status: "invalid")
    assert_not r.valid?
  end

  test "active? for running status" do
    assert runs(:active_run).active?
  end

  test "active? for pending status" do
    assert runs(:pending_run).active?
  end

  test "not active? for completed" do
    assert_not runs(:completed_run).active?
  end

  test "not active? for failed" do
    assert_not runs(:failed_run).active?
  end

  test "active scope returns active statuses" do
    active = Run.active
    active.each do |r|
      assert_includes ["pending", "running", "awaiting_approval"], r.status
    end
  end

  test "recent scope applies ordering" do
    runs = Run.recent
    assert runs.any?
    assert_equal "created_at", runs.order_values.first.expr.name
  end

  test "duration returns elapsed time" do
    run = runs(:completed_run)
    assert_kind_of Float, run.duration
    assert run.duration.positive?
  end

  test "duration returns nil when not started" do
    run = Run.new(status: "pending")
    assert_nil run.duration
  end

  test "duration uses current time for active runs" do
    run = runs(:active_run)
    d1 = run.duration
    assert d1.positive?
  end

  test "has_many run_steps" do
    run = runs(:completed_run)
    assert run.run_steps.any?
  end

  test "usage_stats aggregates run_step stats" do
    run = runs(:completed_run)
    stats = run.usage_stats
    assert_not_nil stats
    assert_in_delta 0.0523, stats[:cost_usd], 0.001
    assert_equal 15_000, stats[:input_tokens]
    assert_equal 3000, stats[:output_tokens]
    assert_equal 5, stats[:num_turns]
  end

  test "usage_stats returns nil when no stats" do
    run = runs(:pending_run)
    assert_nil run.usage_stats
  end

  test "destroying run destroys run_steps" do
    run = runs(:completed_run)
    assert_difference "RunStep.count", -run.run_steps.count do
      run.destroy
    end
  end

  test "awaiting_approval status is valid" do
    r = Run.new(workflow: workflows(:deploy), status: "awaiting_approval")
    assert r.valid?
  end

  test "active? is true for awaiting_approval status" do
    assert runs(:awaiting_run).active?
  end

  test "active scope includes awaiting_approval runs" do
    active = Run.active
    assert_includes active.map(&:status), "awaiting_approval"
  end

  test "awaiting_approval? returns true for awaiting_approval run" do
    assert runs(:awaiting_run).awaiting_approval?
  end

  test "awaiting_approval? returns false for running run" do
    assert_not runs(:active_run).awaiting_approval?
  end

  test "awaiting_run_step returns the awaiting run_step" do
    run = runs(:awaiting_run)
    rs = run_steps(:awaiting_step_run_step)
    assert_equal rs, run.awaiting_run_step
  end

  test "awaiting_run_step returns nil when none" do
    assert_nil runs(:active_run).awaiting_run_step
  end
end
