require "test_helper"

class DataExporterTest < ActiveSupport::TestCase
  test "exports valid structure" do
    data = DataExporter.new.call
    export = data[:seneschal_export]

    assert_equal 1, export[:version]
    assert_not_nil export[:exported_at]
    assert export[:skills].is_a?(Array)
    assert export[:step_templates].is_a?(Array)
    assert export[:projects].is_a?(Array)
  end

  test "exports skills with project reference" do
    data = DataExporter.new.call
    skills = data[:seneschal_export][:skills]

    shared = skills.find { |s| s[:name] == skills(:shared_skill).name }
    assert_not_nil shared
    assert_nil shared[:project_name]

    project_skill = skills.find { |s| s[:name] == skills(:project_skill).name }
    assert_not_nil project_skill
    assert_equal "Seneschal", project_skill[:project_name]
  end

  test "exports projects with nested workflows and steps" do
    data = DataExporter.new.call
    projects = data[:seneschal_export][:projects]

    seneschal = projects.find { |p| p[:name] == "Seneschal" }
    assert_not_nil seneschal
    assert seneschal[:workflows].any?

    deploy = seneschal[:workflows].find { |w| w[:name] == "Deploy Pipeline" }
    assert_not_nil deploy
    assert deploy[:steps].any?
  end

  test "exports tasks with workflow reference" do
    data = DataExporter.new.call
    projects = data[:seneschal_export][:projects]

    seneschal = projects.find { |p| p[:name] == "Seneschal" }
    tasks = seneschal[:tasks]
    assert tasks.any?

    ready_task = tasks.find { |t| t[:title] == pipeline_tasks(:ready_task).title }
    assert_not_nil ready_task
    assert_not_nil ready_task[:workflow_name]
  end

  test "exports step templates" do
    data = DataExporter.new.call
    templates = data[:seneschal_export][:step_templates]
    assert templates.any?

    cmd = templates.find { |t| t[:name] == "Git Checkout Main" }
    assert_not_nil cmd
    assert_equal "command", cmd[:step_type]
  end

  test "export is valid JSON" do
    data = DataExporter.new.call
    json = data.to_json
    parsed = JSON.parse(json)
    assert_equal 1, parsed["seneschal_export"]["version"]
  end

  test "exporter includes project_groups and project skip_permissions" do
    projects(:seneschal).update!(project_group: project_groups(:frontend), skip_permissions: true)
    data = DataExporter.new.call
    export = data[:seneschal_export]

    assert(export[:project_groups].any? { |g| g[:name] == "Frontend" })

    seneschal_entry = export[:projects].find { |p| p[:name] == "Seneschal" }
    assert_not_nil seneschal_entry
    assert_equal "Frontend", seneschal_entry[:project_group_name]
    assert_equal true, seneschal_entry[:skip_permissions]
  end
end
