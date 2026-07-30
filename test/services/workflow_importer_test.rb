require "test_helper"

class WorkflowImporterTest < ActiveSupport::TestCase
  setup do
    @source_workflow = workflows(:deploy)
    @target_project = projects(:other_project)
    @payload = WorkflowExporter.new(@source_workflow).call
  end

  test "round-trips export → import into a new project" do
    expected_step_count = @source_workflow.steps.count

    result = WorkflowImporter.new(@payload, target_project: @target_project).call

    assert_equal @target_project.id, result.workflow.project_id
    assert_equal expected_step_count, result.workflow.steps.count
    assert_equal @source_workflow.steps.order(:position).map(&:name),
                 result.workflow.steps.order(:position).map(&:name)
    assert_equal :new, result.mode
  end

  test "a legacy export carrying workflow trigger fields still imports" do
    legacy = @payload.deep_dup
    legacy[:seneschal_workflow_export][:workflow][:trigger_type] = "cron"
    legacy[:seneschal_workflow_export][:workflow][:trigger_config] = { "cron" => "0 * * * *" }

    result = WorkflowImporter.new(legacy, target_project: @target_project).call

    assert_equal :new, result.mode
    assert_equal @source_workflow.steps.count, result.workflow.steps.count
    assert_not result.workflow.respond_to?(:trigger_type)
  end

  test "creates shared skill on target when missing" do
    Skill.shared.where(name: "ingest_feature").destroy_all

    result = WorkflowImporter.new(@payload, target_project: @target_project).call

    created = Skill.shared.find_by(name: "ingest_feature")
    assert_not_nil created, "expected new shared skill to be created"
    assert_includes result.created_skills, created
    skill_step = result.workflow.steps.find { |s| s.step_type == "skill" }
    assert_equal created.id, skill_step.skill_id
  end

  test "reuses existing shared skill in target" do
    existing = skills(:shared_skill)

    result = WorkflowImporter.new(@payload, target_project: @target_project).call

    assert_empty result.created_skills.select(&:shared?)
    skill_step = result.workflow.steps.find { |s| s.step_type == "skill" }
    assert_equal existing.id, skill_step.skill_id
  end

  test "creates project-scoped skill in target when missing" do
    wf = projects(:seneschal).workflows.create!(name: "Schemaless")
    wf.steps.create!(
      name: "Check", step_type: "skill", skill: skills(:project_skill),
      position: 1, max_retries: 0, timeout: 300, config: {}
    )
    payload = WorkflowExporter.new(wf).call

    result = WorkflowImporter.new(payload, target_project: @target_project).call

    created = @target_project.skills.find_by(name: "deploy_check")
    assert_not_nil created
    assert_includes result.created_skills, created
    assert_equal created.id, result.workflow.steps.first.skill_id
  end

  test "name conflicts get '(import N)' suffix in :new mode" do
    @target_project.workflows.create!(name: "Deploy Pipeline")

    result = WorkflowImporter.new(@payload, target_project: @target_project).call

    assert_equal "Deploy Pipeline (import 2)", result.workflow.name
  end

  test "honors name_override when provided" do
    result = WorkflowImporter.new(@payload, target_project: @target_project, name_override: "Renamed Flow").call

    assert_equal "Renamed Flow", result.workflow.name
  end

  test "replace mode keeps workflow id, swaps steps and config" do
    existing = @target_project.workflows.create!(
      name: "Existing", description: "old", config: { "runner" => "claude_cli" }
    )
    existing.steps.create!(
      name: "Old step", step_type: "command", body: "echo old",
      position: 1, timeout: 60, max_retries: 0, config: {}
    )

    result = WorkflowImporter.new(@payload,
                                  target_project: @target_project,
                                  mode: :replace,
                                  replace_workflow: existing).call

    assert_equal existing.id, result.workflow.id
    assert_equal :replace, result.mode
    assert_equal @source_workflow.steps.count, result.workflow.reload.steps.count
    assert_equal @source_workflow.description, result.workflow.description
    assert_not(result.workflow.steps.exists?(name: "Old step"))
  end

  test "replace mode rejects workflow from a different project" do
    other_wf = workflows(:deploy) # belongs to seneschal, not @target_project

    assert_raises ArgumentError do
      WorkflowImporter.new(@payload,
                           target_project: @target_project,
                           mode: :replace,
                           replace_workflow: other_wf).call
    end
  end

  test "replace mode requires a replace_workflow" do
    assert_raises ArgumentError do
      WorkflowImporter.new(@payload, target_project: @target_project, mode: :replace).call
    end
  end

  test "rejects unknown version" do
    bad = { seneschal_workflow_export: { version: 999, workflow: {} } }
    assert_raises ArgumentError do
      WorkflowImporter.new(bad, target_project: @target_project).call
    end
  end

  test "rejects missing envelope" do
    assert_raises ArgumentError do
      WorkflowImporter.new({ wrong_root: 1 }, target_project: @target_project).call
    end
  end

  test "reuses existing JsonSchema by name without overwriting" do
    schema = json_schemas(:person_schema)
    @source_workflow.steps.first.update!(config: { "json_schema_id" => schema.id })
    payload = WorkflowExporter.new(@source_workflow.reload).call

    # Mutate the export's schema body so we can verify the importer doesn't overwrite.
    payload[:seneschal_workflow_export][:json_schemas].first[:body] = '{"type":"string"}'

    assert_no_difference "JsonSchema.count" do
      WorkflowImporter.new(payload, target_project: @target_project).call
    end
    assert_equal schema.body, schema.reload.body
  end

  test "creates a new JsonSchema when name is unknown to the target" do
    schema = json_schemas(:person_schema)
    @source_workflow.steps.first.update!(config: { "json_schema_id" => schema.id })
    payload = WorkflowExporter.new(@source_workflow.reload).call

    JsonSchema.where(name: "person").destroy_all

    assert_difference "JsonSchema.count", 1 do
      result = WorkflowImporter.new(payload, target_project: @target_project).call
      assert_equal 1, result.created_schemas.size
      assert_equal "person", result.created_schemas.first.name
    end
  end

  test "attaches json_schema_id from the schema_ref name on import" do
    schema = json_schemas(:person_schema)
    @source_workflow.steps.first.update!(config: { "json_schema_id" => schema.id })
    payload = WorkflowExporter.new(@source_workflow.reload).call

    result = WorkflowImporter.new(payload, target_project: @target_project).call

    target_first_step = result.workflow.steps.order(:position).first
    assert_equal schema.id, target_first_step.config["json_schema_id"]
  end

  test "transaction rolls back on failure" do
    payload = @payload.deep_dup
    payload[:seneschal_workflow_export][:workflow][:steps].last[:step_type] = "not_a_real_type"

    assert_no_difference ["Workflow.count", "Step.count"] do
      assert_raises ActiveRecord::RecordInvalid do
        WorkflowImporter.new(payload, target_project: @target_project).call
      end
    end
  end
end
