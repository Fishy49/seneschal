require "test_helper"

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
end
