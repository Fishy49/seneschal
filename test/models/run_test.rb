require "test_helper"

class RunTest < ActiveSupport::TestCase
  test "started_by_label prefers the launching user" do
    run = runs(:completed_run)
    run.update!(started_by: users(:admin))
    assert_equal users(:admin).email, run.started_by_label
  end

  test "started_by_label falls back to the trigger reason" do
    run = runs(:completed_run)
    run.update!(started_by: nil, input: { "trigger_reason" => "cron" })
    assert_equal "cron", run.started_by_label
  end

  test "started_by_label falls back to system" do
    run = runs(:completed_run)
    run.update!(started_by: nil, input: {})
    assert_equal "system", run.started_by_label
  end

  test "deleting a user nullifies attribution instead of deleting the run" do
    user = User.create!(email: "temp-attribution@test.com", password: "password12")
    run = runs(:completed_run)
    run.update!(started_by: user)

    user.destroy!
    assert Run.exists?(run.id)
    assert_nil run.reload.started_by_id
  end

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

  test "ordinal counts this run's position among its task's runs" do
    task = pipeline_tasks(:completed_task)
    first = runs(:completed_run)
    second = Run.create!(workflow: first.workflow, pipeline_task: task, status: "pending", context: {}, input: {})

    assert_equal 1, first.ordinal
    assert_equal 2, second.ordinal
  end

  test "ordinal is nil for a run with no task" do
    assert_nil runs(:failed_run).ordinal
  end
  test "thread_items interleaves comments, events, and seals, hiding duplicates" do
    run = runs(:awaiting_run)
    step = run_steps(:awaiting_step_run_step)

    started = Event.record("run.started", subject: run, user: users(:admin))
    started.update!(created_at: 3.hours.ago)
    comment = run.comments.create!(user: users(:admin), body: "watch the migration")
    comment.update!(created_at: 2.hours.ago)
    seal = step.approval_events.create!(user: users(:admin), action: "approved", comment: "ship it")
    seal.update!(created_at: 1.hour.ago)
    hidden = Event.record("run.approved", subject: run, user: users(:admin))

    items = run.thread_items
    assert_equal [started, comment, seal], items & [started, comment, seal]
    assert_not_includes items, hidden
  end
end
