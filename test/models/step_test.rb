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

  test "available_variables_for marks schema-bound root outputs as queryable" do
    workflow = workflows(:deploy)
    workflow.steps.destroy_all
    schema = json_schemas(:person_schema)
    workflow.steps.create!(
      name: "Producer", step_type: "prompt", body: "go",
      position: 1, timeout: 30, max_retries: 0,
      config: { "produces" => ["person"], "json_schema_id" => schema.id }
    )

    vars = Step.available_variables_for(workflow, 2)
    by_name = vars.index_by { |v| v["name"] }

    assert by_name["person"]["queryable"], "schema-bound root should be queryable"
    assert_not by_name["person.name"]["queryable"], "sub-paths are not directly queryable"
    assert_not by_name["task_title"]["queryable"], "globals are not queryable"
  end

  test "queryable_variable_schemas returns root => schema for schema-bound producers" do
    workflow = workflows(:deploy)
    workflow.steps.destroy_all
    schema = json_schemas(:person_schema)
    workflow.steps.create!(
      name: "Producer", step_type: "prompt", body: "go",
      position: 1, timeout: 30, max_retries: 0,
      config: { "produces" => ["person"], "json_schema_id" => schema.id }
    )

    map = Step.queryable_variable_schemas(workflow, 2)
    assert_equal({ "person" => schema }, map)
  end

  test "queries reads config queries array" do
    s = Step.new(config: { "queries" => ["foundation"] })
    assert_equal ["foundation"], s.queries
  end

  test "pr step is valid with a title in config" do
    s = Step.new(
      name: "Open PR", workflow: workflows(:deploy),
      step_type: "pr", position: 10, timeout: 60,
      config: { "title" => "feat: ${task_title}" }
    )
    assert s.valid?, s.errors.full_messages.inspect
  end

  test "pr step is invalid without a title" do
    s = Step.new(
      name: "Open PR", workflow: workflows(:deploy),
      step_type: "pr", position: 10, timeout: 60,
      config: {}
    )
    assert_not s.valid?
    assert s.errors.full_messages.any? { |m| m.match?(/title/i) }, s.errors.full_messages.inspect
  end

  test "pr step is invalid with a blank title" do
    s = Step.new(
      name: "Open PR", workflow: workflows(:deploy),
      step_type: "pr", position: 10, timeout: 60,
      config: { "title" => "   " }
    )
    assert_not s.valid?
    assert s.errors.full_messages.any? { |m| m.match?(/title/i) }, s.errors.full_messages.inspect
  end

  test "pr step output_variables include the conventional triplet plus declared produces" do
    s = Step.new(
      name: "Open PR", workflow: workflows(:deploy),
      step_type: "pr", position: 10, timeout: 60,
      config: { "title" => "x", "produces" => ["pr_number", "extra_tag"] }
    )
    outputs = s.output_variables
    assert_equal "pr_number", outputs.first, "pr_number should remain first for downstream consumers"
    assert_includes outputs, "pr_url"
    assert_includes outputs, "branch_name"
    assert_includes outputs, "extra_tag"
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

  # --- inherit_skill_defaults ---

  test "skill step inherits default_json_schema + default_output_variable from its skill" do
    skill = skills(:shared_skill)
    skill.update!(default_json_schema: json_schemas(:simple_schema),
                  default_output_variable: "the_plan")
    step = Step.new(
      name: "Inheriting", workflow: workflows(:deploy),
      step_type: "skill", skill: skill,
      position: 11, timeout: 300
    )
    assert step.valid?
    assert_equal json_schemas(:simple_schema).id, step.config["json_schema_id"]
    assert_equal ["the_plan"], step.config["produces"]
  end

  test "explicit config wins over inherited defaults" do
    skill = skills(:shared_skill)
    other_schema = JsonSchema.create!(name: "other_test_schema", body: '{"type":"object"}')
    skill.update!(default_json_schema: json_schemas(:simple_schema),
                  default_output_variable: "default_var")
    step = Step.new(
      name: "Overriding", workflow: workflows(:deploy),
      step_type: "skill", skill: skill,
      position: 12, timeout: 300,
      config: { "json_schema_id" => other_schema.id, "produces" => ["custom"] }
    )
    assert step.valid?
    assert_equal other_schema.id, step.config["json_schema_id"]
    assert_equal ["custom"], step.config["produces"]
  end

  test "inheritance does not apply when the skill has no defaults" do
    step = Step.new(
      name: "Plain", workflow: workflows(:deploy),
      step_type: "skill", skill: skills(:shared_skill),
      position: 13, timeout: 300
    )
    assert step.valid?
    assert_nil step.config["json_schema_id"]
    assert_nil step.config["produces"]
  end

  test "inheritance does not apply to non-skill step types" do
    skills(:shared_skill).update!(default_json_schema: json_schemas(:simple_schema),
                                  default_output_variable: "x")
    step = Step.new(
      name: "Script", workflow: workflows(:deploy),
      step_type: "script", body: "echo hi",
      position: 14, timeout: 60
    )
    assert step.valid?
    assert_nil step.config["json_schema_id"]
  end
end
