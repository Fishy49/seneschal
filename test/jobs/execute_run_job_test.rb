require "test_helper"
require "tmpdir"
require "fileutils"

class ExecuteRunJobTest < ActiveJob::TestCase
  setup do
    @job = ExecuteRunJob.new
    @step = steps(:skill_step)
  end

  # Regression test: previously, input_context was discarded entirely if it
  # contained no ${variable} placeholders. Static instructions like
  # "Name the branch X" should be passed through unchanged.
  test "resolve_input_context preserves static text without variables" do
    @step.input_context = "Name the branch \"game-test-1\""
    assert_equal "Name the branch \"game-test-1\"", @job.send(:resolve_input_context, @step, {})
  end

  test "resolve_input_context interpolates variables" do
    @step.input_context = "Use branch ${branch_name} for the task"
    result = @job.send(:resolve_input_context, @step, { "branch_name" => "feature/x" })
    assert_equal "Use branch feature/x for the task", result
  end

  test "resolve_input_context accepts symbol keys in context" do
    @step.input_context = "Hello ${name}"
    assert_equal "Hello Rick", @job.send(:resolve_input_context, @step, { name: "Rick" })
  end

  test "resolve_input_context blanks out missing variables but keeps surrounding text" do
    @step.input_context = "Use branch ${missing_var} please"
    assert_equal "Use branch  please", @job.send(:resolve_input_context, @step, {})
  end

  test "resolve_input_context returns nil for blank input_context" do
    @step.input_context = ""
    assert_nil @job.send(:resolve_input_context, @step, {})

    @step.input_context = nil
    assert_nil @job.send(:resolve_input_context, @step, {})
  end

  test "resolve_input_context returns nil when result is whitespace only" do
    @step.input_context = "  ${missing}  "
    assert_nil @job.send(:resolve_input_context, @step, {})
  end

  test "resolve_input_context mixes static text and variables" do
    @step.input_context = "Branch: ${branch}\nAlso name it carefully."
    result = @job.send(:resolve_input_context, @step, { "branch" => "main" })
    assert_equal "Branch: main\nAlso name it carefully.", result
  end

  test "append_rejection_context concatenates feedback to resolved input" do
    result = @job.send(:append_rejection_context, "base text", "fix it")
    assert_includes result, "--- Operator rejection feedback (re-run) ---\nfix it"
    assert result.start_with?("base text")
  end

  test "append_rejection_context with nil base and non-empty rejection" do
    result = @job.send(:append_rejection_context, nil, "fix it")
    assert result.present?
    assert_includes result, "fix it"
  end

  test "append_rejection_context returns base unchanged when rejection is nil" do
    result = @job.send(:append_rejection_context, "base", nil)
    assert_equal "base", result
  end

  test "append_rejection_context returns base unchanged when rejection is blank" do
    result = @job.send(:append_rejection_context, "base", "   ")
    assert_equal "base", result
  end

  test "job pauses run in awaiting_approval after manual_approval step passes" do
    project = projects(:seneschal)
    tmpdir = Dir.mktmpdir
    project.update!(repo_status: "ready", local_path: tmpdir)

    workflow = workflows(:deploy)
    workflow.steps.destroy_all

    step = workflow.steps.create!(
      name: "Pause Here", step_type: "command", body: "echo paused",
      position: 1, manual_approval: true, timeout: 30, max_retries: 0, config: {}
    )

    run = workflow.runs.create!(status: "pending", context: {}, input: {})

    fake_result = StepExecutor::Result.new(exit_code: 0, stdout: "paused\n", stderr: "", stream_events: nil)
    StepExecutor.any_instance.stubs(:execute).returns(fake_result)

    ExecuteRunJob.new.perform(run)

    run.reload
    assert_equal "awaiting_approval", run.status
    awaiting_rs = run.run_steps.find_by(status: "awaiting_approval")
    assert_not_nil awaiting_rs
    assert_equal "paused\n", awaiting_rs.output
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
    workflow.steps.destroy_all
  end

  test "after_approval skips the approved step and processes only later steps" do
    project = projects(:seneschal)
    tmpdir = Dir.mktmpdir
    project.update!(repo_status: "ready", local_path: tmpdir)

    workflow = workflows(:deploy)
    workflow.steps.destroy_all

    step1 = workflow.steps.create!(
      name: "First", step_type: "command", body: "echo a",
      position: 1, manual_approval: true, timeout: 30, max_retries: 0, config: {}
    )
    step2 = workflow.steps.create!(
      name: "Second", step_type: "command", body: "echo b",
      position: 2, timeout: 30, max_retries: 0, config: {}
    )

    run = workflow.runs.create!(status: "awaiting_approval", started_at: 1.minute.ago, context: {}, input: {})
    run.run_steps.create!(step: step1, status: "passed", attempt: 1, position: 1,
                          started_at: 1.minute.ago, finished_at: 50.seconds.ago, duration: 10.0)

    fake_result = StepExecutor::Result.new(exit_code: 0, stdout: "b\n", stderr: "", stream_events: nil)
    StepExecutor.any_instance.stubs(:execute).returns(fake_result)

    ExecuteRunJob.new.perform(run, step1.id, after_approval: true)

    run.reload
    assert_equal "completed", run.status
    assert_equal "passed", run.run_steps.find_by(step: step1).reload.status
    second_rs = run.run_steps.find_by(step: step2)
    assert_not_nil second_rs
    assert_equal "passed", second_rs.status
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
    workflow.steps.destroy_all
  end
end
