require "test_helper"

class DataImporterTest < ActiveSupport::TestCase
  setup do
    @export_data = DataExporter.new.call
  end

  test "round-trips export and import" do
    original_projects = Project.count
    original_skills = Skill.count

    stats = DataImporter.new(@export_data).call

    assert_equal original_projects, Project.count
    assert_equal original_skills, Skill.count
    assert stats[:projects].positive?
    assert stats[:skills].positive?
  end

  test "wipes existing data before import" do
    assert Run.any?, "precondition: runs exist"

    DataImporter.new(@export_data).call

    assert_equal 0, Run.count
    assert_equal 0, RunStep.count
  end

  test "preserves skill-step links" do
    DataImporter.new(@export_data).call

    skill_steps = Step.where(step_type: "skill")
    skill_steps.each do |step|
      assert_not_nil step.skill, "Step '#{step.name}' should have a skill"
    end
  end

  test "preserves workflow-task links" do
    DataImporter.new(@export_data).call

    non_draft = PipelineTask.where.not(status: "draft")
    non_draft.each do |task|
      assert_not_nil task.workflow, "Non-draft task '#{task.title}' should have a workflow"
    end
  end

  test "imports step templates with skill links" do
    DataImporter.new(@export_data).call

    skill_templates = StepTemplate.where(step_type: "skill")
    skill_templates.each do |t|
      assert_not_nil t.skill, "Skill template '#{t.name}' should have a skill"
    end
  end

  test "rejects invalid file" do
    assert_raises ArgumentError do
      DataImporter.new({ bad: "data" }).call
    end
  end

  test "rejects unsupported version" do
    bad = { seneschal_export: { version: 999 } }
    assert_raises ArgumentError do
      DataImporter.new(bad).call
    end
  end

  test "rolls back on import failure" do
    original_count = Project.count

    bad_data = @export_data.deep_dup
    bad_data[:seneschal_export][:projects] << { name: nil, repo_url: nil, local_path: nil }

    assert_raises ActiveRecord::StatementInvalid do
      DataImporter.new(bad_data).call
    end

    # Transaction rolled back — original data intact
    assert_equal original_count, Project.count
  end

  test "falls back to draft for tasks without workflow" do
    data = {
      seneschal_export: {
        version: 1,
        exported_at: Time.current.iso8601,
        skills: [],
        step_templates: [],
        projects: [{
          name: "Test", repo_url: "https://github.com/t/t.git", local_path: "/tmp/t",
          workflows: [],
          tasks: [{ title: "Orphan", body: "no workflow", kind: "feature", status: "ready", workflow_name: "nonexistent" }]
        }]
      }
    }

    DataImporter.new(data).call
    task = PipelineTask.find_by(title: "Orphan")
    assert_equal "draft", task.status
  end
end
