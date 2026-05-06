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

  test "prepend_consumes_context resolves dotted sub-paths from JSON producer" do
    @step.update!(config: @step.config.merge("consumes" => ["review.summary", "review.meta.author"]))
    context = { "review" => '{"summary":"looks good","meta":{"author":"rick"}}' }
    executor = StepExecutor.new(@step, context, @ready.local_path)

    prompt = executor.send(:prepend_consumes_context, "skill body")

    assert_includes prompt, "<review.summary>\nlooks good\n</review.summary>"
    assert_includes prompt, "<review.meta.author>\nrick\n</review.meta.author>"
  end

  test "interpolate_string resolves dotted JSON paths in ${var.path}" do
    context = { "review" => '{"summary":"ok","meta":{"author":"rick"}}' }
    executor = StepExecutor.new(@step, context, @ready.local_path)

    result = executor.send(:interpolate_string, "summary=${review.summary}, by=${review.meta.author}")

    assert_equal "summary=ok, by=rick", result
  end

  test "interpolate_string leaves unresolved placeholders unchanged" do
    executor = StepExecutor.new(@step, { "review" => '{"summary":"ok"}' }, @ready.local_path)
    result = executor.send(:interpolate_string, "missing=${review.nope}")
    assert_equal "missing=${review.nope}", result
  end

  test "execute_skill prepends project markdown_context to prompt" do
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    prompt = executor.send(:prepend_project_context, "skill body here")

    assert_includes prompt, "## Project Context"
    assert_includes prompt, "Always use double quotes for strings"
    assert prompt.end_with?("skill body here")
  end

  test "prepend_project_context handles ad-hoc step via run.workflow.project" do
    workflow = workflows(:deploy)
    run = workflow.runs.create!(status: "running", context: {})
    ad_hoc_step = Step.create!(
      run: run,
      name: "ad-hoc",
      step_type: "skill",
      skill: skills(:project_skill),
      position: 1,
      timeout: 300,
      max_retries: 0,
      config: {}
    )
    executor = StepExecutor.new(ad_hoc_step, {}, @ready.local_path)
    prompt = executor.send(:prepend_project_context, "body")

    assert_includes prompt, "Project Context"
  end

  test "prepend_project_context returns prompt unchanged when markdown_context is blank" do
    @ready.update!(markdown_context: nil)
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    prompt = executor.send(:prepend_project_context, "raw prompt")

    assert_equal "raw prompt", prompt
  end

  test "prepend_project_context reads markdown_context fresh at execution time" do
    executor1 = StepExecutor.new(@step, {}, @ready.local_path)
    prompt1 = executor1.send(:prepend_project_context, "body")

    @ready.update!(markdown_context: "# Brand New\n\nFresh policy.")

    executor2 = StepExecutor.new(Step.find(@step.id), {}, @ready.local_path)
    prompt2 = executor2.send(:prepend_project_context, "body")

    assert_includes prompt1, "Always use double quotes"
    assert_includes prompt2, "Brand New"
    assert_includes prompt2, "Fresh policy"
    assert_not_includes prompt2, "Always use double quotes"
  end

  test "skill cmd uses --dangerously-skip-permissions when project.skip_permissions" do
    projects(:seneschal).update!(skip_permissions: true)
    step = steps(:skill_step)
    executor = StepExecutor.new(step, {}, projects(:seneschal).local_path)
    cmd = executor.send(:build_skill_cmd, "hi")
    assert_includes cmd, "--dangerously-skip-permissions"
    assert_not_includes cmd, "--permission-mode"
    assert_not_includes cmd, "--allowedTools"
  end

  test "skill cmd uses --permission-mode dontAsk when skip_permissions false" do
    projects(:seneschal).update!(skip_permissions: false)
    step = steps(:skill_step)
    executor = StepExecutor.new(step, {}, projects(:seneschal).local_path)
    cmd = executor.send(:build_skill_cmd, "hi")
    assert_includes cmd, "--permission-mode"
    idx = cmd.index("--permission-mode")
    assert_equal "dontAsk", cmd[idx + 1]
    assert_includes cmd, "--allowedTools"
    assert_not_includes cmd, "--dangerously-skip-permissions"
  end

  test "skip_permissions on one project does not affect another" do
    projects(:seneschal).update!(skip_permissions: true)
    other = projects(:other_project)
    other.update!(skip_permissions: false)
    workflow = other.workflows.create!(name: "Other Wf", trigger_type: "manual")
    other_step = workflow.steps.create!(
      name: "Other Step",
      step_type: "skill",
      skill: skills(:shared_skill),
      position: 1,
      timeout: 300,
      max_retries: 0,
      config: {}
    )
    FileUtils.mkdir_p(other.local_path)
    executor = StepExecutor.new(other_step, {}, other.local_path)
    cmd = executor.send(:build_skill_cmd, "hi")
    assert_includes cmd, "--permission-mode"
    assert_not_includes cmd, "--dangerously-skip-permissions"
  end

  test "append_schema_instructions includes schema body" do
    schema = json_schemas(:person_schema)
    step = steps(:skill_step)
    step.update!(config: step.config.merge("json_schema_id" => schema.id))
    executor = StepExecutor.new(step, {}, @ready.local_path)

    result = executor.send(:append_schema_instructions, "skill body")

    assert result.start_with?("skill body")
    assert_includes result, "Required JSON Output Schema"
    assert_includes result, "person"
    assert_includes result, '"type"'
    assert_includes result, '"object"'
  end

  test "append_schema_instructions names the produces output variable" do
    schema = json_schemas(:person_schema)
    step = steps(:skill_step)
    step.update!(config: step.config.merge("json_schema_id" => schema.id, "produces" => ["person_payload"]))
    executor = StepExecutor.new(step, {}, @ready.local_path)

    result = executor.send(:append_schema_instructions, "skill body")

    assert_includes result, "person_payload"
    assert_includes result, "```output"
  end

  test "json_validator passes when value matches schema" do
    schema = json_schemas(:person_schema)
    step = workflows(:deploy).steps.create!(
      name: "v", step_type: "json_validator",
      position: 50, timeout: 30, max_retries: 0,
      config: { "json_schema_id" => schema.id, "source_variable" => "payload" }
    )
    executor = StepExecutor.new(step, { "payload" => '{"name":"Rick","age":42}' }, @ready.local_path)
    result = executor.execute
    assert result.passed?, result.stderr
    assert_includes result.stdout, "Validated 'payload'"
  end

  test "json_validator fails when value does not match schema" do
    schema = json_schemas(:person_schema)
    step = workflows(:deploy).steps.create!(
      name: "v", step_type: "json_validator",
      position: 50, timeout: 30, max_retries: 0,
      config: { "json_schema_id" => schema.id, "source_variable" => "payload" }
    )
    executor = StepExecutor.new(step, { "payload" => '{"age":42}' }, @ready.local_path)
    result = executor.execute
    assert_equal 1, result.exit_code
    assert_includes result.stderr, "name"
  end

  test "json_validator fails when value is not valid JSON" do
    schema = json_schemas(:person_schema)
    step = workflows(:deploy).steps.create!(
      name: "v", step_type: "json_validator",
      position: 50, timeout: 30, max_retries: 0,
      config: { "json_schema_id" => schema.id, "source_variable" => "payload" }
    )
    executor = StepExecutor.new(step, { "payload" => "not json" }, @ready.local_path)
    result = executor.execute
    assert_not result.passed?
    assert_includes result.stderr, "is not valid JSON"
  end

  test "json_validator fails when source variable not in context" do
    schema = json_schemas(:person_schema)
    step = workflows(:deploy).steps.create!(
      name: "v", step_type: "json_validator",
      position: 50, timeout: 30, max_retries: 0,
      config: { "json_schema_id" => schema.id, "source_variable" => "missing_var" }
    )
    executor = StepExecutor.new(step, {}, @ready.local_path)
    result = executor.execute
    assert_not result.passed?
    assert_includes result.stderr, "missing_var"
  end

  test "json_validator fails when schema not found" do
    step = workflows(:deploy).steps.create!(
      name: "v", step_type: "json_validator",
      position: 50, timeout: 30, max_retries: 0,
      config: { "json_schema_id" => 999_999, "source_variable" => "payload" }
    )
    executor = StepExecutor.new(step, { "payload" => "{}" }, @ready.local_path)
    result = executor.execute
    assert_not result.passed?
    assert_includes result.stderr, "JSON Schema not found"
  end
end
