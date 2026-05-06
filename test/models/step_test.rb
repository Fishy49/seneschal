require "test_helper"

class StepTest < ActiveSupport::TestCase
  test "valid skill step" do
    s = Step.new(
      name: "New Step", workflow: workflows(:deploy),
      step_type: "skill", skill: skills(:shared_skill),
      position: 10, timeout: 300
    )
    assert s.valid?
  end

  test "valid command step" do
    s = Step.new(
      name: "Cmd", workflow: workflows(:deploy),
      step_type: "command", body: "echo hi",
      position: 10, timeout: 60
    )
    assert s.valid?
  end

  test "requires name" do
    s = steps(:skill_step).dup
    s.name = nil
    assert_not s.valid?
  end

  test "requires position" do
    s = steps(:skill_step).dup
    s.position = nil
    assert_not s.valid?
  end

  test "position must be positive" do
    s = steps(:skill_step).dup
    s.position = 0
    assert_not s.valid?
  end

  test "validates step_type inclusion" do
    s = steps(:skill_step).dup
    s.step_type = "invalid"
    assert_not s.valid?
  end

  test "skill step requires skill" do
    s = Step.new(
      name: "No Skill", workflow: workflows(:deploy),
      step_type: "skill", position: 10
    )
    assert_not s.valid?
    assert_includes s.errors[:skill], "can't be blank"
  end

  test "script step requires body" do
    s = Step.new(
      name: "No Body", workflow: workflows(:deploy),
      step_type: "script", position: 10
    )
    assert_not s.valid?
    assert_includes s.errors[:body], "can't be blank"
  end

  test "command step requires body" do
    s = Step.new(
      name: "No Body", workflow: workflows(:deploy),
      step_type: "command", position: 10
    )
    assert_not s.valid?
    assert_includes s.errors[:body], "can't be blank"
  end

  test "prompt_body renders skill template with context" do
    step = steps(:skill_step)
    result = step.prompt_body("task_title" => "Add auth")
    assert_includes result, "Add auth"
  end

  test "prompt_body returns nil for non-skill steps" do
    step = steps(:command_step)
    assert_nil step.prompt_body({})
  end

  test "max_retries cannot be negative" do
    s = steps(:skill_step).dup
    s.max_retries = -1
    assert_not s.valid?
  end

  test "timeout must be positive" do
    s = steps(:skill_step).dup
    s.timeout = 0
    assert_not s.valid?
  end

  test "context_project_ids returns integers deduped" do
    s = steps(:skill_step)
    s.update!(config: s.config.merge("context_projects" => ["1", 2, "2", 3]))
    assert_equal [1, 2, 3], s.context_project_ids
  end

  test "ready_context_projects includes only cloned projects" do
    ready = projects(:seneschal) # repo_status: ready
    not_ready = projects(:other_project) # repo_status: not_cloned
    FileUtils.mkdir_p(ready.local_path)
    s = steps(:skill_step)
    s.update!(config: s.config.merge("context_projects" => [ready.id, not_ready.id]))

    assert_equal [ready], s.ready_context_projects
  end

  test "ready_context_projects skips unknown ids without raising" do
    s = steps(:skill_step)
    s.update!(config: s.config.merge("context_projects" => [9_999_999]))
    assert_equal [], s.ready_context_projects
  end

  test "manual_approval? returns false by default" do
    s = steps(:skill_step)
    assert_not s.manual_approval?
  end

  test "manual_approval? returns true when set" do
    s = steps(:approval_step)
    assert s.manual_approval?
  end

  test "valid json_validator step" do
    s = Step.new(
      name: "v", workflow: workflows(:deploy),
      step_type: "json_validator", position: 10, timeout: 30, max_retries: 0,
      config: { "json_schema_id" => json_schemas(:person_schema).id, "source_variable" => "person_payload" }
    )
    assert s.valid?, s.errors.full_messages.inspect
  end

  test "json_validator requires json_schema_id and source_variable" do
    s = Step.new(
      name: "v", workflow: workflows(:deploy),
      step_type: "json_validator", position: 10, timeout: 30, max_retries: 0,
      config: {}
    )
    assert_not s.valid?
    assert_includes s.errors[:base], "JSON validator step requires a json_schema_id"
    assert_includes s.errors[:base], "JSON validator step requires a source_variable"
  end

  test "json_schema returns associated schema" do
    schema = json_schemas(:person_schema)
    s = steps(:skill_step)
    s.config = s.config.merge("json_schema_id" => schema.id)
    assert_equal schema, s.json_schema
  end

  test "json_schema returns nil when not set" do
    s = steps(:skill_step)
    assert_nil s.json_schema
  end

  test "validator_source_variable returns config value" do
    s = Step.new(config: { "source_variable" => "payload" })
    assert_equal "payload", s.validator_source_variable
  end

  test "available_variables_for includes globals, prior produces, and schema sub-paths" do
    workflow = workflows(:deploy)
    workflow.steps.destroy_all
    schema = json_schemas(:person_schema)
    workflow.steps.create!(
      name: "Producer", step_type: "prompt", body: "go",
      position: 1, timeout: 30, max_retries: 0,
      config: { "produces" => ["person"], "json_schema_id" => schema.id }
    )

    vars = Step.available_variables_for(workflow, 2)
    names = vars.pluck("name")

    Step::GLOBAL_VARIABLES.each { |g| assert_includes names, g }
    assert_includes names, "person"
    assert_includes names, "person.name"
    assert_includes names, "person.age"
  end

  test "available_variables_for surfaces context_fetch context_key and schema sub-paths" do
    workflow = workflows(:deploy)
    workflow.steps.destroy_all
    schema = json_schemas(:person_schema)
    workflow.steps.create!(
      name: "Read flags", step_type: "context_fetch",
      position: 1, timeout: 30, max_retries: 0,
      config: { "method" => "project_file", "path" => "p.json",
                "context_key" => "flags", "json_schema_id" => schema.id }
    )

    names = Step.available_variables_for(workflow, 2).pluck("name")
    assert_includes names, "flags"
    assert_includes names, "flags.name"
    assert_includes names, "flags.age"
  end
end
