require "test_helper"

class RunStepTest < ActiveSupport::TestCase
  test "valid run_step" do
    rs = RunStep.new(run: runs(:active_run), step: steps(:command_step), status: "pending", attempt: 1)
    assert rs.valid?
  end

  test "validates status inclusion" do
    rs = RunStep.new(run: runs(:active_run), step: steps(:command_step), status: "invalid", attempt: 1)
    assert_not rs.valid?
  end

  test "attempt must be positive" do
    rs = RunStep.new(run: runs(:active_run), step: steps(:command_step), status: "pending", attempt: 0)
    assert_not rs.valid?
  end

  test "all statuses are valid" do
    RunStep::STATUSES.each do |s|
      rs = RunStep.new(run: runs(:active_run), step: steps(:command_step), status: s, attempt: 1)
      assert rs.valid?, "Expected status '#{s}' to be valid"
    end
  end

  test "usage_stats extracts from stream_log" do
    rs = run_steps(:passed_step)
    stats = rs.usage_stats
    assert_not_nil stats
    assert_equal 0.0523, stats[:cost_usd]
    assert_equal 15_000, stats[:input_tokens]
    assert_equal 3000, stats[:output_tokens]
    assert_equal 5000, stats[:cache_read_tokens]
    assert_equal 1000, stats[:cache_creation_tokens]
    assert_equal 45_000, stats[:duration_ms]
    assert_equal 5, stats[:num_turns]
  end

  test "usage_stats returns nil without stream_log" do
    rs = run_steps(:passed_command_step)
    assert_nil rs.usage_stats
  end

  test "usage_stats returns nil for non-array stream_log" do
    rs = RunStep.new(stream_log: "not an array")
    assert_nil rs.usage_stats
  end

  test "usage_stats returns nil without result event" do
    rs = RunStep.new(stream_log: [{ "type" => "system", "model" => "claude" }])
    assert_nil rs.usage_stats
  end

  test "awaiting_approval is a valid status" do
    rs = RunStep.new(run: runs(:active_run), step: steps(:command_step), status: "awaiting_approval", attempt: 1)
    assert rs.valid?
  end

  test "rejection_context can be stored and retrieved" do
    rs = run_steps(:awaiting_step_run_step)
    rs.update!(rejection_context: "Use a different branch.")
    assert_equal "Use a different branch.", rs.reload.rejection_context
  end

  test "rejection_context can be nil" do
    rs = run_steps(:passed_step)
    assert_nil rs.rejection_context
  end
end
