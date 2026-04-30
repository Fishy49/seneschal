require "test_helper"

class WorkflowCopierTest < ActiveSupport::TestCase
  setup do
    @source = workflows(:deploy)
    @target = projects(:other_project)
  end

  test "copies workflow with all steps to target project" do
    expected_step_count = @source.steps.count
    result = WorkflowCopier.new(@source, @target).call

    assert_equal @target.id, result.workflow.project_id
    assert_equal expected_step_count, result.workflow.steps.count
    assert_equal @source.steps.order(:position).map(&:name),
                 result.workflow.steps.order(:position).map(&:name)
  end

  test "appends '(copy N)' suffix when name conflicts" do
    @target.workflows.create!(name: "Deploy Pipeline", trigger_type: "manual")
    result = WorkflowCopier.new(@source, @target).call
    assert_equal "Deploy Pipeline (copy 2)", result.workflow.name
  end

  test "appends incrementing suffix for multiple conflicts" do
    @target.workflows.create!(name: "Deploy Pipeline", trigger_type: "manual")
    @target.workflows.create!(name: "Deploy Pipeline (copy 2)", trigger_type: "manual")
    result = WorkflowCopier.new(@source, @target).call
    assert_equal "Deploy Pipeline (copy 3)", result.workflow.name
  end

  test "shared skills are reused as-is in target project" do
    result = WorkflowCopier.new(@source, @target).call
    shared_step = result.workflow.steps.joins(:skill).find_by(skills: { project_id: nil })
    assert_not_nil shared_step
    assert_equal skills(:shared_skill).id, shared_step.skill_id
    assert_empty result.missing_skills
  end

  test "reports project-scoped skills missing from target" do
    wf = projects(:seneschal).workflows.create!(name: "Skill Wf", trigger_type: "manual")
    wf.steps.create!(
      name: "Check Step",
      step_type: "skill",
      skill: skills(:project_skill),
      position: 1,
      timeout: 300,
      max_retries: 0,
      config: {}
    )
    result = WorkflowCopier.new(wf, @target).call
    assert_includes result.missing_skills, "Seneschal/deploy_check"
    assert_equal 1, result.workflow.steps.count
    assert_equal skills(:project_skill).id, result.workflow.steps.first.skill_id
  end

  test "uses target project's skill of same name when present" do
    target_skill = @target.skills.create!(name: "deploy_check", body: "check")
    wf = projects(:seneschal).workflows.create!(name: "Skill Wf 2", trigger_type: "manual")
    wf.steps.create!(
      name: "Check Step",
      step_type: "skill",
      skill: skills(:project_skill),
      position: 1,
      timeout: 300,
      max_retries: 0,
      config: {}
    )
    result = WorkflowCopier.new(wf, @target).call
    assert_empty result.missing_skills
    assert_equal target_skill.id, result.workflow.steps.first.skill_id
  end

  test "strips context_projects from copied step config" do
    wf = projects(:seneschal).workflows.create!(name: "Context Wf", trigger_type: "manual")
    wf.steps.create!(
      name: "Context Step",
      step_type: "command",
      body: "echo hi",
      position: 1,
      timeout: 300,
      max_retries: 0,
      config: { "context_projects" => [99] }
    )
    result = WorkflowCopier.new(wf, @target).call
    assert_nil result.workflow.steps.first.config["context_projects"]
  end

  test "copies workflow description and trigger attributes" do
    result = WorkflowCopier.new(@source, @target).call
    assert_equal @source.description, result.workflow.description
    assert_equal @source.trigger_type, result.workflow.trigger_type
  end

  test "result includes copied_steps" do
    result = WorkflowCopier.new(@source, @target).call
    assert_equal @source.steps.count, result.copied_steps.count
  end

  test "group-scoped skills are reused when target project is in the same group" do
    same_group_target = Project.create!(
      name: "FrontendSibling",
      repo_url: "https://github.com/t/sibling.git",
      local_path: Rails.root.join("tmp", "test_repos", "sibling").to_s,
      project_group: project_groups(:frontend),
      repo_status: "ready"
    )
    wf = projects(:seneschal).workflows.create!(name: "Group Wf", trigger_type: "manual")
    wf.steps.create!(
      name: "Lint Step",
      step_type: "skill",
      skill: skills(:group_skill),
      position: 1,
      timeout: 300,
      max_retries: 0,
      config: {}
    )
    result = WorkflowCopier.new(wf, same_group_target).call
    assert_empty result.missing_skills
    assert_equal skills(:group_skill).id, result.workflow.steps.first.skill_id
  end

  test "reports group-scoped skills missing from a target in a different group" do
    wf = projects(:seneschal).workflows.create!(name: "Group Wf 2", trigger_type: "manual")
    wf.steps.create!(
      name: "Lint Step",
      step_type: "skill",
      skill: skills(:group_skill),
      position: 1,
      timeout: 300,
      max_retries: 0,
      config: {}
    )
    result = WorkflowCopier.new(wf, @target).call
    assert_includes result.missing_skills, "Frontend/lint_check"
  end
end
