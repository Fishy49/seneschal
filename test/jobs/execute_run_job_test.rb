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
    workflow = setup_workflow_with_ready_project!
    workflow.steps.create!(
      name: "Pause Here", step_type: "command", body: "echo paused",
      position: 1, manual_approval: true, timeout: 30, max_retries: 0, config: {}
    )
    run = workflow.runs.create!(status: "pending", context: {}, input: {})

    with_stubbed_step_executor(stdout: "paused\n") do
      ExecuteRunJob.new.perform(run)
    end

    run.reload
    assert_equal "awaiting_approval", run.status
    awaiting_rs = run.run_steps.find_by(status: "awaiting_approval")
    assert_not_nil awaiting_rs
    assert_equal "paused\n", awaiting_rs.output
  ensure
    cleanup_workflow_with_ready_project!(workflow)
  end

  test "after_approval skips the approved step and processes only later steps" do
    workflow = setup_workflow_with_ready_project!
    step1, step2 = create_two_step_workflow(workflow)
    run = workflow.runs.create!(status: "awaiting_approval", started_at: 1.minute.ago, context: {}, input: {})
    run.run_steps.create!(step: step1, status: "passed", attempt: 1, position: 1,
                          started_at: 1.minute.ago, finished_at: 50.seconds.ago, duration: 10.0)

    with_stubbed_step_executor(stdout: "b\n") do
      ExecuteRunJob.new.perform(run, step1.id, after_approval: true)
    end

    run.reload
    assert_equal "completed", run.status
    assert_equal "passed", run.run_steps.find_by(step: step1).reload.status
    second_rs = run.run_steps.find_by(step: step2)
    assert_not_nil second_rs
    assert_equal "passed", second_rs.status
  ensure
    cleanup_workflow_with_ready_project!(workflow)
  end

  test "json_validator failure triggers run failure" do
    workflow = setup_workflow_with_ready_project!
    producer_step = workflow.steps.create!(
      name: "Producer", step_type: "prompt", body: "produce payload",
      position: 1, timeout: 30, max_retries: 0, config: { "produces" => ["payload"] }
    )
    validator_step = workflow.steps.create!(
      name: "Validator", step_type: "json_validator", position: 2, timeout: 30, max_retries: 0,
      config: { "json_schema_id" => json_schemas(:person_schema).id, "source_variable" => "payload" }
    )
    run = workflow.runs.create!(status: "pending", context: {}, input: {})

    stub_step_executor_for_step(producer_step, stdout: "```output\npayload: |\n  {\"age\":42}\n```") do
      ExecuteRunJob.new.perform(run)
    end

    run.reload
    assert_equal "failed", run.status
    validator_rs = run.run_steps.find_by(step: validator_step)
    assert_not_nil validator_rs
    assert_equal "failed", validator_rs.status
    assert_includes validator_rs.error_output.to_s, "name"
  ensure
    cleanup_workflow_with_ready_project!(workflow)
  end

  test "scope_context keeps parent variable when consumes references a sub-path" do
    workflow = setup_workflow_with_ready_project!
    _step1, step2 = create_two_step_workflow(workflow,
                                             step1_config: { "produces" => ["review"] },
                                             step2_config: { "consumes" => ["review.summary"] })
    run = workflow.runs.create!(status: "running",
                                context: { "review" => '{"summary":"ok"}', "unrelated" => "drop me" },
                                input: {})

    scoped = ExecuteRunJob.new.send(:scope_context, step2, run.context)

    assert_equal '{"summary":"ok"}', scoped["review"]
    assert_not scoped.key?("unrelated")
  ensure
    cleanup_workflow_with_ready_project!(workflow)
  end

  test "after_approval queue retains pipeline context for subsequent steps" do
    workflow = setup_workflow_with_ready_project!
    step1, step2 = create_two_step_workflow(workflow,
                                            step1_config: { "produces" => ["greeting"] },
                                            step2_config: { "consumes" => ["greeting"] })
    run = workflow.runs.create!(status: "awaiting_approval", started_at: 1.minute.ago,
                                context: { "greeting" => "hello" }, input: {})
    run.run_steps.create!(step: step1, status: "passed", attempt: 1, position: 1,
                          started_at: 1.minute.ago, finished_at: 50.seconds.ago, duration: 10.0)

    captured = capture_step_executor_contexts do
      ExecuteRunJob.new.perform(run, step1.id, after_approval: true)
    end

    run.reload
    assert_equal "completed", run.status
    assert_not captured.key?(step1.id), "step1 should not be re-executed after approval"
    assert_equal "hello", captured[step2.id]&.fetch("greeting", nil)
    assert_equal "passed", run.run_steps.find_by(step: step2).status
  ensure
    cleanup_workflow_with_ready_project!(workflow)
  end

  private

  def setup_workflow_with_ready_project!
    project = projects(:seneschal)
    @_test_tmpdir = Dir.mktmpdir
    project.update!(repo_status: "ready", local_path: @_test_tmpdir)
    workflow = workflows(:deploy)
    workflow.steps.destroy_all
    workflow
  end

  def cleanup_workflow_with_ready_project!(workflow)
    FileUtils.rm_rf(@_test_tmpdir) if @_test_tmpdir
    workflow&.steps&.destroy_all
  end

  def create_two_step_workflow(workflow, step1_config: {}, step2_config: {})
    step1 = workflow.steps.create!(
      name: "First", step_type: "command", body: "echo a",
      position: 1, manual_approval: true, timeout: 30, max_retries: 0, config: step1_config
    )
    step2 = workflow.steps.create!(
      name: "Second", step_type: "command", body: "echo b",
      position: 2, timeout: 30, max_retries: 0, config: step2_config
    )
    [step1, step2]
  end

  def with_stubbed_step_executor(stdout: "", &)
    fake_result = StepExecutor::Result.new(exit_code: 0, stdout: stdout, stderr: "", stream_events: nil)
    factory = ->(*_args, **_kwargs) { fake_executor(fake_result) }
    stub_step_executor_new(factory, &)
  end

  # Stubs only the named step's executor, falling through to the real executor for any other step.
  def stub_step_executor_for_step(stubbed_step, stdout: "", &)
    fake_result = StepExecutor::Result.new(exit_code: 0, stdout: stdout, stderr: "", stream_events: nil)
    factory = lambda do |step, context, repo_path, **kwargs|
      next fake_executor(fake_result) if step.id == stubbed_step.id

      StepExecutor.__original_new(step, context, repo_path, **kwargs)
    end
    stub_step_executor_new(factory, &)
  end

  def capture_step_executor_contexts(&)
    captured = {}
    fake_result = StepExecutor::Result.new(exit_code: 0, stdout: "ok\n", stderr: "", stream_events: nil)
    factory = lambda do |step, context, _repo_path, **_kwargs|
      captured[step.id] = context
      fake_executor(fake_result)
    end
    stub_step_executor_new(factory, &)
    captured
  end

  def fake_executor(result)
    executor = Object.new
    executor.define_singleton_method(:execute) { |&_blk| result }
    executor
  end

  # Replaces StepExecutor.new with a callable factory for the duration of the
  # block, then restores the original. Used in lieu of Mocha-style any-instance
  # stubbing — Minitest 6 dropped Object#stub, and Mocha is not in the Gemfile.
  def stub_step_executor_new(factory)
    metaclass = class << StepExecutor; self; end
    metaclass.send(:alias_method, :__original_new, :new)
    metaclass.send(:define_method, :new) do |*args, **kwargs|
      factory.call(*args, **kwargs)
    end
    yield
  ensure
    metaclass.send(:remove_method, :new)
    metaclass.send(:alias_method, :new, :__original_new)
    metaclass.send(:remove_method, :__original_new)
  end
end
