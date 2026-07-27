require "test_helper"

class WorkflowExporterTest < ActiveSupport::TestCase
  setup do
    @workflow = workflows(:deploy)
  end

  test "produces a well-formed envelope" do
    payload = WorkflowExporter.new(@workflow).call[:seneschal_workflow_export]

    assert_equal WorkflowExporter::FORMAT_VERSION, payload[:version]
    assert_not_nil payload[:exported_at]
    assert_equal "Seneschal", payload[:source_project_name]
    assert_equal @workflow.name, payload[:workflow][:name]
  end

  test "serializes steps in position order with all relevant fields" do
    payload = WorkflowExporter.new(@workflow).call[:seneschal_workflow_export]
    steps = payload[:workflow][:steps]

    assert_equal @workflow.steps.count, steps.size
    assert_equal(@workflow.steps.order(:position).map(&:position), steps.pluck(:position))

    skill_step = steps.find { |s| s[:step_type] == "skill" }
    assert_equal({ scope: "shared", name: "ingest_feature" }, skill_step[:skill_ref])
  end

  test "strips runtime-only step config keys" do
    schema = json_schemas(:person_schema)
    @workflow.steps.first.update!(
      config: { "json_schema_id" => schema.id, "context_projects" => [42], "produces" => ["plan"] }
    )

    payload = WorkflowExporter.new(@workflow).call[:seneschal_workflow_export]
    step = payload[:workflow][:steps].first

    assert_not step[:config].key?("json_schema_id")
    assert_not step[:config].key?("context_projects")
    assert_equal ["plan"], step[:config]["produces"]
    assert_equal "person", step[:json_schema_ref]
  end

  test "includes referenced skill payload with SKILL.md content" do
    payload = WorkflowExporter.new(@workflow).call[:seneschal_workflow_export]
    skill = payload[:skills].find { |s| s[:name] == "ingest_feature" }

    assert_not_nil skill
    assert_equal "shared", skill[:scope]
    assert_equal "global", skill[:source_kind]
    assert_includes skill[:skill_md_content], "name: ingest_feature"
  end

  test "includes JSON schemas referenced by steps or skill defaults" do
    schema = json_schemas(:person_schema)
    @workflow.steps.first.update!(config: { "json_schema_id" => schema.id })

    payload = WorkflowExporter.new(@workflow).call[:seneschal_workflow_export]
    names = payload[:json_schemas].pluck(:name)
    assert_includes names, "person"
  end

  test "step skill_ref is nil for non-skill steps" do
    payload = WorkflowExporter.new(@workflow).call[:seneschal_workflow_export]
    command_step = payload[:workflow][:steps].find { |s| s[:step_type] == "command" }
    assert_nil command_step[:skill_ref]
  end

  test "exports the workflow config blob" do
    @workflow.update!(config: { "runner" => "claude_sdk" })
    payload = WorkflowExporter.new(@workflow).call[:seneschal_workflow_export]

    assert_equal({ "runner" => "claude_sdk" }, payload[:workflow][:config])
  end

  test "no longer exports the retired workflow trigger fields" do
    payload = WorkflowExporter.new(@workflow).call[:seneschal_workflow_export]

    assert_not payload[:workflow].key?(:trigger_type)
    assert_not payload[:workflow].key?(:trigger_config)
  end
end
