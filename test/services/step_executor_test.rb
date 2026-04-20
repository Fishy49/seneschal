require "test_helper"

class StepExecutorTest < ActiveSupport::TestCase
  setup do
    @ready = projects(:seneschal)
    FileUtils.mkdir_p(@ready.local_path)
    @step = steps(:skill_step)
  end

  test "skill cmd omits --add-dir when no context projects" do
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    cmd = executor.send(:build_skill_cmd, "hello")
    assert_not_includes cmd, "--add-dir"
  end

  test "skill cmd appends --add-dir for each ready context project" do
    @step.update!(config: @step.config.merge("context_projects" => [@ready.id]))
    executor = StepExecutor.new(@step, {}, "/tmp/other")
    cmd = executor.send(:build_skill_cmd, "hello")

    add_dir_indexes = cmd.each_index.select { |i| cmd[i] == "--add-dir" }
    assert_equal 1, add_dir_indexes.size
    assert_equal @ready.local_path, cmd[add_dir_indexes.first + 1]
  end

  test "skill cmd skips --add-dir for not-cloned projects" do
    not_ready = projects(:other_project)
    @step.update!(config: @step.config.merge("context_projects" => [not_ready.id]))
    executor = StepExecutor.new(@step, {}, "/tmp/other")
    cmd = executor.send(:build_skill_cmd, "hello")

    assert_not_includes cmd, "--add-dir"
  end

  test "append_context_projects adds section naming each directory" do
    @step.update!(config: @step.config.merge("context_projects" => [@ready.id]))
    executor = StepExecutor.new(@step, {}, "/tmp/other")
    prompt = executor.send(:append_context_projects, "original prompt")

    assert_includes prompt, "original prompt"
    assert_includes prompt, "Available Project Directories"
    assert_includes prompt, @ready.name
    assert_includes prompt, @ready.local_path.to_s
  end

  test "prepend_consumes_context injects consumed variables as tagged blocks" do
    @step.update!(config: @step.config.merge("consumes" => ["task_plan", "branch_name"]))
    context = { "task_plan" => "Ship the feature", "branch_name" => "feature/foo" }
    executor = StepExecutor.new(@step, context, @ready.local_path)

    prompt = executor.send(:prepend_consumes_context, "skill body here")

    assert_includes prompt, "Input Variables"
    assert_includes prompt, "<task_plan>\nShip the feature\n</task_plan>"
    assert_includes prompt, "<branch_name>\nfeature/foo\n</branch_name>"
    assert prompt.end_with?("skill body here")
  end

  test "prepend_consumes_context skips variables with missing or blank values" do
    @step.update!(config: @step.config.merge("consumes" => ["present", "missing", "blank"]))
    context = { "present" => "yes", "blank" => "   " }
    executor = StepExecutor.new(@step, context, @ready.local_path)

    prompt = executor.send(:prepend_consumes_context, "skill body")

    assert_includes prompt, "<present>\nyes\n</present>"
    assert_not_includes prompt, "<missing>"
    assert_not_includes prompt, "<blank>"
  end

  test "prepend_consumes_context returns prompt unchanged when no values resolve" do
    @step.update!(config: @step.config.merge("consumes" => ["missing"]))
    executor = StepExecutor.new(@step, {}, @ready.local_path)

    prompt = executor.send(:prepend_consumes_context, "skill body")

    assert_equal "skill body", prompt
  end
end
