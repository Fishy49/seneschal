require "test_helper"

class StepExecutorTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
  setup do
    @ready = projects(:seneschal)
    FileUtils.mkdir_p(@ready.local_path)
    @step = steps(:skill_step)
  end

  # Helper: build the CLI command StepExecutor would produce for a given
  # prompt, by routing through the same `runner_call_kwargs` → `build_cmd`
  # path the executor uses at runtime. Lets these tests keep asserting on
  # the final cmd array shape even though command construction moved to
  # Runners::ClaudeCLI.
  def built_skill_cmd(executor, prompt, stream: false)
    kwargs = executor.send(:runner_call_kwargs, prompt: prompt, stream: stream)
    executor.runner.build_cmd(**kwargs)
  end

  test "skill cmd omits --add-dir when no context projects" do
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    cmd = built_skill_cmd(executor, "hello")
    assert_not_includes cmd, "--add-dir"
  end

  test "skill cmd appends --add-dir for each ready context project" do
    @step.update!(config: @step.config.merge("context_projects" => [@ready.id]))
    executor = StepExecutor.new(@step, {}, "/tmp/other")
    cmd = built_skill_cmd(executor, "hello")

    add_dir_indexes = cmd.each_index.select { |i| cmd[i] == "--add-dir" }
    assert_equal 1, add_dir_indexes.size
    assert_equal @ready.local_path, cmd[add_dir_indexes.first + 1]
  end

  test "skill cmd skips --add-dir for not-cloned projects" do
    not_ready = projects(:other_project)
    @step.update!(config: @step.config.merge("context_projects" => [not_ready.id]))
    executor = StepExecutor.new(@step, {}, "/tmp/other")
    cmd = built_skill_cmd(executor, "hello")

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
    cmd = built_skill_cmd(executor, "hi")
    assert_includes cmd, "--dangerously-skip-permissions"
    assert_not_includes cmd, "--permission-mode"
    assert_not_includes cmd, "--allowedTools"
  end

  test "skill cmd uses --permission-mode dontAsk when skip_permissions false" do
    projects(:seneschal).update!(skip_permissions: false)
    step = steps(:skill_step)
    executor = StepExecutor.new(step, {}, projects(:seneschal).local_path)
    cmd = built_skill_cmd(executor, "hi")
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
    cmd = built_skill_cmd(executor, "hi")
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

  test "validation_errors_for returns nil when output matches schema" do
    schema = json_schemas(:person_schema)
    @step.update!(config: @step.config.merge("json_schema_id" => schema.id, "produces" => ["person"]))
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    result = StepExecutor::Result.new(
      exit_code: 0, stdout: "Done.\n```output\nperson: |\n  {\"name\":\"Rick\",\"age\":42}\n```\n", stderr: ""
    )

    assert_nil executor.send(:validation_errors_for, result)
  end

  test "validation_errors_for reports schema errors when output does not conform" do
    schema = json_schemas(:person_schema)
    @step.update!(config: @step.config.merge("json_schema_id" => schema.id, "produces" => ["person"]))
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    result = StepExecutor::Result.new(
      exit_code: 0, stdout: "```output\nperson: |\n  {\"age\":42}\n```\n", stderr: ""
    )

    errors = executor.send(:validation_errors_for, result)
    assert errors.is_a?(Array)
    assert errors.any? { |e| e.include?("name") }, errors.inspect
  end

  test "validation_errors_for reports parse error when output isn't JSON" do
    schema = json_schemas(:person_schema)
    @step.update!(config: @step.config.merge("json_schema_id" => schema.id, "produces" => ["person"]))
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    result = StepExecutor::Result.new(
      exit_code: 0, stdout: "```output\nperson: not json\n```\n", stderr: ""
    )

    errors = executor.send(:validation_errors_for, result)
    assert errors.any? { |e| e.include?("not valid JSON") }, errors.inspect
  end

  test "validation_errors_for reports missing variable when output block absent" do
    schema = json_schemas(:person_schema)
    @step.update!(config: @step.config.merge("json_schema_id" => schema.id, "produces" => ["person"]))
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    result = StepExecutor::Result.new(exit_code: 0, stdout: "I'm done!", stderr: "")

    errors = executor.send(:validation_errors_for, result)
    assert errors.any? { |e| e.include?("missing") }, errors.inspect
  end

  test "validate_with_session_retry returns initial result when output is valid" do
    schema = json_schemas(:person_schema)
    @step.update!(config: @step.config.merge("json_schema_id" => schema.id, "produces" => ["person"]))
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    calls = 0
    executor.runner.define_singleton_method(:execute) do |**_kwargs, &_block|
      calls += 1
      flunk("should not retry")
    end

    initial = StepExecutor::Result.new(
      exit_code: 0, stdout: "```output\nperson: |\n  {\"name\":\"Rick\"}\n```",
      stderr: "", stream_events: [{ "session_id" => "abc" }]
    )
    final = executor.send(:validate_with_session_retry, initial)
    assert_equal 0, calls
    assert_equal initial, final
  end

  test "validate_with_session_retry resumes session with feedback and accepts corrected output" do
    schema = json_schemas(:person_schema)
    @step.update!(config: @step.config.merge("json_schema_id" => schema.id, "produces" => ["person"]))
    executor = StepExecutor.new(@step, {}, @ready.local_path)

    captured_kwargs = nil
    executor.runner.define_singleton_method(:execute) do |**kwargs, &_block|
      captured_kwargs = kwargs
      StepExecutor::Result.new(
        exit_code: 0, stdout: "```output\nperson: |\n  {\"name\":\"Rick\",\"age\":42}\n```",
        stderr: "", stream_events: [{ "session_id" => "sess-1" }], session_id: "sess-1"
      )
    end

    initial = StepExecutor::Result.new(
      exit_code: 0, stdout: "```output\nperson: |\n  {\"age\":42}\n```",
      stderr: "", stream_events: [{ "session_id" => "sess-1" }], session_id: "sess-1"
    )
    final = executor.send(:validate_with_session_retry, initial)

    assert final.passed?, final.stderr
    assert_equal "sess-1", captured_kwargs[:resume_session_id]
    assert_includes captured_kwargs[:resume_message], "did not validate"
    assert_includes captured_kwargs[:resume_message], "person"
    assert_includes captured_kwargs[:resume_message], "name"
  end

  test "validate_with_session_retry fails after max attempts with combined errors" do
    schema = json_schemas(:person_schema)
    @step.update!(config: @step.config.merge(
      "json_schema_id" => schema.id, "produces" => ["person"], "validation_max_attempts" => 2
    ))
    executor = StepExecutor.new(@step, {}, @ready.local_path)

    bad_stdout = "```output\nperson: |\n  {\"age\":1}\n```"
    executor.runner.define_singleton_method(:execute) do |**_kwargs, &_block|
      StepExecutor::Result.new(
        exit_code: 0, stdout: bad_stdout, stderr: "",
        stream_events: [{ "session_id" => "sess" }], session_id: "sess"
      )
    end

    initial = StepExecutor::Result.new(
      exit_code: 0, stdout: bad_stdout, stderr: "",
      stream_events: [{ "session_id" => "sess" }], session_id: "sess"
    )
    final = executor.send(:validate_with_session_retry, initial)

    assert_not final.passed?
    assert_includes final.stderr, "validation failed after 2 attempts"
    assert_includes final.stderr, "name"
  end

  test "validate_with_session_retry fails immediately when no session id can be captured" do
    schema = json_schemas(:person_schema)
    @step.update!(config: @step.config.merge("json_schema_id" => schema.id, "produces" => ["person"]))
    executor = StepExecutor.new(@step, {}, @ready.local_path)

    initial = StepExecutor::Result.new(
      exit_code: 0, stdout: "```output\nperson: |\n  {\"age\":1}\n```", stderr: "", stream_events: nil
    )
    final = executor.send(:validate_with_session_retry, initial)

    assert_not final.passed?
    assert_includes final.stderr, "no Claude session id"
  end

  test "validate_with_session_retry skips validation when validation_max_attempts is zero" do
    schema = json_schemas(:person_schema)
    @step.update!(config: @step.config.merge(
      "json_schema_id" => schema.id, "produces" => ["person"], "validation_max_attempts" => 0
    ))
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    executor.runner.define_singleton_method(:execute) { |**_kwargs, &_block| flunk("should not retry") }

    initial = StepExecutor::Result.new(
      exit_code: 0, stdout: "```output\nperson: |\n  {\"age\":1}\n```", stderr: "", stream_events: nil
    )
    assert_equal initial, executor.send(:validate_with_session_retry, initial)
  end

  test "prepend_queryable_context lists each queryable variable with its schema and wrapper usage" do
    schema = json_schemas(:person_schema)
    workflow = workflows(:deploy)
    workflow.steps.destroy_all
    workflow.steps.create!(
      name: "Producer", step_type: "prompt", body: "go", position: 1,
      timeout: 30, max_retries: 0,
      config: { "produces" => ["person"], "json_schema_id" => schema.id }
    )
    consumer = workflow.steps.create!(
      name: "Consumer", step_type: "skill", skill: skills(:shared_skill),
      position: 2, timeout: 30, max_retries: 0,
      config: { "queries" => ["person"] }
    )
    executor = StepExecutor.new(consumer, {}, @ready.local_path)
    prompt = executor.send(:prepend_queryable_context, "BODY")

    assert_includes prompt, "Queryable Context"
    assert_includes prompt, "seneschal-context"
    assert_includes prompt, "person"
    assert_includes prompt, schema.body
    assert prompt.end_with?("BODY")
  end

  test "env_vars include SENESCHAL_* keys when queries are active" do
    schema = json_schemas(:person_schema)
    workflow = workflows(:deploy)
    workflow.steps.destroy_all
    workflow.steps.create!(
      name: "Producer", step_type: "prompt", body: "go", position: 1,
      timeout: 30, max_retries: 0,
      config: { "produces" => ["person"], "json_schema_id" => schema.id }
    )
    consumer = workflow.steps.create!(
      name: "Consumer", step_type: "skill", skill: skills(:shared_skill),
      position: 2, timeout: 30, max_retries: 0,
      config: { "queries" => ["person"] }
    )
    run = workflow.runs.create!(status: "running", context: {}, input: {})
    consumer.update!(run_id: run.id)
    executor = StepExecutor.new(consumer, {}, @ready.local_path, run_step_id: 7)
    env = executor.send(:env_vars)

    assert_equal "person", env["SENESCHAL_QUERYABLE_VARS"]
    assert_equal "7", env["SENESCHAL_RUN_STEP_ID"]
    assert_equal run.id.to_s, env["SENESCHAL_RUN_ID"]
    assert env["SENESCHAL_DB_PATH"].present?
    assert_includes env["PATH"], Rails.root.join("bin").to_s
  end

  test "env_vars stay clean when no queries are configured" do
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    env = executor.send(:env_vars)

    assert_not env.key?("SENESCHAL_QUERYABLE_VARS")
    assert_not env.key?("SENESCHAL_DB_PATH")
  end

  test "context_fetch project_file reads file from project repo" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "config.json"), '{"flag":true}')
      project = projects(:seneschal)
      project.update!(local_path: dir)
      step = workflows(:deploy).steps.create!(
        name: "fetch", step_type: "context_fetch",
        position: 70, timeout: 30, max_retries: 0,
        config: { "method" => "project_file", "path" => "config.json", "context_key" => "cfg" }
      )

      result = StepExecutor.new(step, {}, dir).execute
      assert result.passed?, result.stderr
      assert_equal '{"flag":true}', result.stdout
    end
  end

  test "context_fetch project_file errors when file is missing" do
    Dir.mktmpdir do |dir|
      step = workflows(:deploy).steps.create!(
        name: "fetch", step_type: "context_fetch",
        position: 71, timeout: 30, max_retries: 0,
        config: { "method" => "project_file", "path" => "missing.json", "context_key" => "cfg" }
      )
      result = StepExecutor.new(step, {}, dir).execute
      assert_not result.passed?
      assert_includes result.stderr, "File not found"
    end
  end

  test "context_fetch project_file rejects path traversal" do
    Dir.mktmpdir do |dir|
      step = workflows(:deploy).steps.create!(
        name: "fetch", step_type: "context_fetch",
        position: 72, timeout: 30, max_retries: 0,
        config: { "method" => "project_file", "path" => "../etc/passwd", "context_key" => "cfg" }
      )
      result = StepExecutor.new(step, {}, dir).execute
      assert_not result.passed?
      assert_includes result.stderr, "escapes the project directory"
    end
  end

  test "runner defaults to ClaudeCLI when no config or Setting overrides" do
    Setting.find_by(key: "default_runner")&.destroy
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    assert_instance_of Runners::ClaudeCLI, executor.runner
  end

  test "runner honors Step.config[runner] over the Setting default" do
    Setting["default_runner"] = "claude_cli"
    @step.update!(config: @step.config.merge("runner" => "claude_sdk"))
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    assert_instance_of Runners::ClaudeSDK, executor.runner
  ensure
    Setting.find_by(key: "default_runner")&.destroy
  end

  test "runner uses Setting[default_runner] when step has no override" do
    Setting["default_runner"] = "claude_sdk"
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    assert_instance_of Runners::ClaudeSDK, executor.runner
  ensure
    Setting.find_by(key: "default_runner")&.destroy
  end

  # Precedence: Step.config["runner"] > Workflow.config["runner"] > Setting > default
  test "runner falls through to Workflow.config[runner] when step has no override" do
    Setting.find_by(key: "default_runner")&.destroy
    @step.workflow.update!(config: @step.workflow.config.merge("runner" => "claude_sdk"))
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    assert_instance_of Runners::ClaudeSDK, executor.runner
  end

  test "Step.config[runner] beats Workflow.config[runner]" do
    @step.workflow.update!(config: @step.workflow.config.merge("runner" => "claude_sdk"))
    @step.update!(config: @step.config.merge("runner" => "claude_cli"))
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    assert_instance_of Runners::ClaudeCLI, executor.runner
  end

  test "Workflow.config[runner] beats Setting[default_runner]" do
    Setting["default_runner"] = "claude_cli"
    @step.workflow.update!(config: @step.workflow.config.merge("runner" => "claude_sdk"))
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    assert_instance_of Runners::ClaudeSDK, executor.runner
  ensure
    Setting.find_by(key: "default_runner")&.destroy
  end

  test "runner can be injected via constructor for tests" do
    fake = Runners::ClaudeCLI.new
    executor = StepExecutor.new(@step, {}, @ready.local_path, runner: fake)
    assert_same fake, executor.runner
  end

  test "runner_call_kwargs assembles the per-step runner contract" do
    @step.update!(config: @step.config.merge(
      "model" => "claude-opus-4-7", "max_turns" => 7, "effort" => "high",
      "allowed_tools" => "Read,Glob"
    ))
    executor = StepExecutor.new(@step, { "branch" => "main" }, @ready.local_path,
                                resolved_input_context: "extra context")
    kwargs = executor.send(:runner_call_kwargs, prompt: "go", stream: true)

    assert_equal "go", kwargs[:prompt]
    assert_equal @ready.local_path, kwargs[:cwd]
    assert_equal "claude-opus-4-7", kwargs[:model]
    assert_equal 7, kwargs[:max_turns]
    assert_equal "high", kwargs[:effort]
    assert_equal "Read,Glob", kwargs[:allowed_tools]
    assert_equal true, kwargs[:stream]
    assert_equal "extra context", kwargs[:env]["INPUT_CONTEXT"]
    assert_equal @ready.local_path, kwargs[:env]["REPO_PATH"]
  end

  test "runner_call_kwargs forwards the parsed JSON Schema body when the step has a schema" do
    schema = json_schemas(:person_schema)
    @step.update!(config: @step.config.merge("json_schema_id" => schema.id))
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    kwargs = executor.send(:runner_call_kwargs, prompt: "go", stream: false)

    assert_equal schema.parsed_body, kwargs[:json_schema]
    assert_equal "object", kwargs[:json_schema]["type"]
  end

  test "runner_call_kwargs sets json_schema to nil when the step has no schema" do
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    kwargs = executor.send(:runner_call_kwargs, prompt: "go", stream: false)

    assert_nil kwargs[:json_schema]
  end

  # Structured-outputs short-circuit: when the runner returns a result with
  # a non-nil structured_output, execute_skill must (a) splice it into
  # stdout as a fenced ```output block so PipelineExtractor sees it via
  # the normal path and (b) skip validate_with_session_retry's prompt-
  # engineered retry loop entirely (the SDK already enforced the schema).
  test "execute_skill splices structured_output into stdout and skips the validation retry loop" do
    schema = json_schemas(:person_schema)
    @step.update!(config: @step.config.merge("json_schema_id" => schema.id, "produces" => ["person"]))
    executor = StepExecutor.new(@step, {}, @ready.local_path)

    calls = 0
    structured = { "name" => "Rick", "age" => 42 }
    executor.runner.define_singleton_method(:execute) do |**_kwargs, &_block|
      calls += 1
      StepExecutor::Result.new(
        exit_code: 0, stdout: "All done.", stderr: "",
        stream_events: [{ "session_id" => "sess-x" }], session_id: "sess-x",
        structured_output: structured
      )
    end

    final = executor.send(:execute_skill)

    assert_equal 1, calls, "runner should be called once — no retry loop"
    assert final.passed?, final.stderr
    assert_includes final.stdout, "```output"
    assert_includes final.stdout, "person:"
    assert_includes final.stdout, JSON.generate(structured)
  end

  test "runner_call_kwargs defaults hooks.confine_writes_to_cwd=true when nothing's set" do
    Setting.find_by(key: "confine_writes_to_cwd")&.destroy
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    kwargs = executor.send(:runner_call_kwargs, prompt: "go", stream: false)
    assert_equal true, kwargs[:hooks]["confine_writes_to_cwd"]
  end

  test "runner_call_kwargs honors Setting[confine_writes_to_cwd]=false" do
    Setting["confine_writes_to_cwd"] = "false"
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    kwargs = executor.send(:runner_call_kwargs, prompt: "go", stream: false)
    assert_equal false, kwargs[:hooks]["confine_writes_to_cwd"]
  ensure
    Setting.find_by(key: "confine_writes_to_cwd")&.destroy
  end

  test "runner_call_kwargs lets a per-step config override the Setting default" do
    Setting["confine_writes_to_cwd"] = "false"
    @step.update!(config: @step.config.merge("confine_writes_to_cwd" => true))
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    kwargs = executor.send(:runner_call_kwargs, prompt: "go", stream: false)
    assert_equal true, kwargs[:hooks]["confine_writes_to_cwd"]
  ensure
    Setting.find_by(key: "confine_writes_to_cwd")&.destroy
  end

  test "runner_call_kwargs forwards Step.config[agents] verbatim when present" do
    agents = {
      "reviewer" => { "description" => "Reviews a diff.", "prompt" => "You are a reviewer.",
                      "tools" => ["Read", "Grep"] }
    }
    @step.update!(config: @step.config.merge("agents" => agents))
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    kwargs = executor.send(:runner_call_kwargs, prompt: "go", stream: false)
    assert_equal agents, kwargs[:agents]
  end

  test "runner_call_kwargs leaves agents nil when no Step.config[agents] is set" do
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    kwargs = executor.send(:runner_call_kwargs, prompt: "go", stream: false)
    assert_nil kwargs[:agents]
  end

  test "runner_call_kwargs prefers Step.config[mcp_servers] over Setting[mcp_servers]" do
    Setting["mcp_servers"] = JSON.dump({ "global" => { "type" => "stdio", "command" => "g" } })
    per_step = { "github" => { "type" => "stdio", "command" => "npx" } }
    @step.update!(config: @step.config.merge("mcp_servers" => per_step))
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    kwargs = executor.send(:runner_call_kwargs, prompt: "go", stream: false)
    assert_equal per_step, kwargs[:mcp_servers]
  ensure
    Setting.find_by(key: "mcp_servers")&.destroy
  end

  test "runner_call_kwargs falls back to Setting[mcp_servers] when Step has no override" do
    global = { "global" => { "type" => "stdio", "command" => "g" } }
    Setting["mcp_servers"] = JSON.dump(global)
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    kwargs = executor.send(:runner_call_kwargs, prompt: "go", stream: false)
    assert_equal global, kwargs[:mcp_servers]
  ensure
    Setting.find_by(key: "mcp_servers")&.destroy
  end

  test "runner_call_kwargs leaves mcp_servers nil when nothing is configured" do
    Setting.find_by(key: "mcp_servers")&.destroy
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    kwargs = executor.send(:runner_call_kwargs, prompt: "go", stream: false)
    assert_nil kwargs[:mcp_servers]
  end

  test "execute_skill leaves stdout untouched when produces.first is blank even if structured_output is present" do
    schema = json_schemas(:person_schema)
    @step.update!(config: @step.config.merge("json_schema_id" => schema.id, "produces" => []))
    executor = StepExecutor.new(@step, {}, @ready.local_path)
    original_stdout = "Original output text."

    executor.runner.define_singleton_method(:execute) do |**_kwargs, &_block|
      StepExecutor::Result.new(
        exit_code: 0, stdout: original_stdout, stderr: "",
        stream_events: nil, session_id: nil,
        structured_output: { "x" => 1 }
      )
    end

    final = executor.send(:execute_skill)
    assert_equal original_stdout, final.stdout
  end

  # ---- self_review ----

  test "Step accepts self_review as a valid step_type" do
    step = Step.new(name: "review", step_type: "self_review",
                    workflow: @step.workflow, position: 999, timeout: 60, max_retries: 0, config: {})
    assert step.valid?, step.errors.full_messages.inspect
  end

  test "execute_self_review forces the read-only tool set regardless of step config" do
    repo_path = setup_review_repo!
    step = create_self_review_step!
    step.update!(config: step.config.merge("allowed_tools" => "Bash,Edit,Write"))
    executor = StepExecutor.new(step, {}, repo_path)

    captured_kwargs = nil
    executor.runner.define_singleton_method(:execute) do |**kwargs, &_block|
      captured_kwargs = kwargs
      StepExecutor::Result.new(exit_code: 0, stdout: "review: PASS", stderr: "")
    end

    executor.execute
    assert_equal StepExecutor::SELF_REVIEW_TOOLS, captured_kwargs[:allowed_tools]
  ensure
    FileUtils.rm_rf(@_review_repo_path) if @_review_repo_path
  end

  test "execute_self_review embeds the diff and a default focus into the prompt" do
    repo_path = setup_review_repo!
    File.write(File.join(repo_path, "added.rb"), "puts 'hi'\n")
    in_review_repo("git", "add", "added.rb")
    in_review_repo("git", "commit", "-q", "-m", "add file on feature branch")

    step = create_self_review_step!
    executor = StepExecutor.new(step, {}, repo_path)

    captured_kwargs = nil
    executor.runner.define_singleton_method(:execute) do |**kwargs, &_block|
      captured_kwargs = kwargs
      StepExecutor::Result.new(exit_code: 0, stdout: "review: PASS", stderr: "")
    end

    executor.execute
    assert_includes captured_kwargs[:prompt], "added.rb"
    assert_includes captured_kwargs[:prompt], "puts 'hi'"
    assert_includes captured_kwargs[:prompt], "correctness, safety"
  end

  # Regression: an attacker-controlled `base_ref` (via Step.config) shouldn't
  # be able to inject a flag into `git diff` — e.g. `--upload-pack=evil`.
  # The strict ref-name regex catches it before argv ever sees it.
  test "execute_self_review refuses unsafe base_ref values without invoking git" do
    repo_path = setup_review_repo!
    step = create_self_review_step!
    step.update!(config: step.config.merge("base_ref" => "--upload-pack=evil"))
    executor = StepExecutor.new(step, {}, repo_path)

    captured_kwargs = nil
    executor.runner.define_singleton_method(:execute) do |**kwargs, &_block|
      captured_kwargs = kwargs
      StepExecutor::Result.new(exit_code: 0, stdout: "review: PASS", stderr: "")
    end

    executor.execute
    assert_includes captured_kwargs[:prompt], "refusing diff"
    assert_includes captured_kwargs[:prompt], "--upload-pack=evil"
  ensure
    FileUtils.rm_rf(@_review_repo_path) if @_review_repo_path
  end

  test "execute_self_review honors a custom focus from step config" do
    repo_path = setup_review_repo!
    step = create_self_review_step!
    step.update!(config: step.config.merge("focus" => "security and SQL injection risk"))
    executor = StepExecutor.new(step, {}, repo_path)

    captured_kwargs = nil
    executor.runner.define_singleton_method(:execute) do |**kwargs, &_block|
      captured_kwargs = kwargs
      StepExecutor::Result.new(exit_code: 0, stdout: "review: PASS", stderr: "")
    end

    executor.execute
    assert_includes captured_kwargs[:prompt], "security and SQL injection risk"
  ensure
    FileUtils.rm_rf(@_review_repo_path) if @_review_repo_path
  end

  test "context_fetch project_file interpolates ${var} in path" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "settings.json"), "{}")
      step = workflows(:deploy).steps.create!(
        name: "fetch", step_type: "context_fetch",
        position: 73, timeout: 30, max_retries: 0,
        config: { "method" => "project_file", "path" => "${file}", "context_key" => "cfg" }
      )
      result = StepExecutor.new(step, { "file" => "settings.json" }, dir).execute
      assert result.passed?, result.stderr
      assert_equal "{}", result.stdout
    end
  end

  private

  # Sets up a temp git repo with one commit on `main` and switches to a
  # `feature` branch — same shape as a Seneschal worktree off origin/HEAD.
  # Cached on @_review_repo_path so the test's `ensure` can clean up.
  def setup_review_repo!
    @_review_repo_path = Dir.mktmpdir("seneschal-review-test-")
    in_review_repo("git", "init", "-q", "-b", "main")
    in_review_repo("git", "config", "user.email", "test@example.com")
    in_review_repo("git", "config", "user.name", "Test")
    File.write(File.join(@_review_repo_path, "README.md"), "hello\n")
    in_review_repo("git", "add", "README.md")
    in_review_repo("git", "commit", "-q", "-m", "init")
    in_review_repo("git", "checkout", "-q", "-b", "feature")
    @_review_repo_path
  end

  def in_review_repo(*cmd)
    _, stderr, status = Open3.capture3(*cmd, chdir: @_review_repo_path)
    raise "git command failed in #{@_review_repo_path}: #{cmd.inspect} (#{stderr})" unless status.success?
  end

  def create_self_review_step!
    workflows(:deploy).steps.create!(
      name: "self_review_step", step_type: "self_review",
      position: 998, timeout: 60, max_retries: 0,
      config: { "produces" => ["review"], "base_ref" => "main" }
    )
  end
end
