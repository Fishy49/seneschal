require "test_helper"

class WorkflowAccessSummaryTest < ActiveSupport::TestCase
  setup do
    @project = projects(:seneschal)
    @project.update!(skip_permissions: false)
    @workflow = @project.workflows.create!(name: "Access under test")
  end

  def labels = WorkflowAccessSummary.for(@workflow.reload).map(&:label)

  def add_step(attributes)
    @workflow.steps.create!({ position: @workflow.steps.count + 1, timeout: 60 }.merge(attributes))
  end

  test "a workflow that touches nothing is read-only" do
    add_step(name: "Look", step_type: "context_fetch")
    assert_equal ["read-only"], labels
  end

  test "a pr step opens PRs" do
    add_step(name: "Ship", step_type: "pr", config: { "title" => "x" })
    assert_includes labels, "opens PRs"
  end

  test "shell steps run shell, under either legacy name" do
    add_step(name: "Build", step_type: "command", body: "make")
    assert_includes labels, "runs shell"

    other = @project.workflows.create!(name: "Legacy shell")
    other.steps.create!(name: "Old", step_type: "script", body: "./x.sh", position: 1, timeout: 60)
    assert_includes WorkflowAccessSummary.for(other).map(&:label), "runs shell"
  end

  test "an agent step with no allowed tools writes files, because blank inherits a default that can" do
    add_step(name: "Implement", step_type: "skill", skill: skills(:shared_skill))
    assert_includes labels, "writes files"
  end

  test "an agent step limited to read-only tools does not write files" do
    add_step(name: "Read only", step_type: "skill", skill: skills(:shared_skill),
             config: { "allowed_tools" => "Read,Grep,Glob" })
    assert_equal ["read-only"], labels
  end

  test "an agent step allowed to edit writes files" do
    add_step(name: "Edits", step_type: "skill", skill: skills(:shared_skill),
             config: { "allowed_tools" => "Read,Edit" })
    assert_includes labels, "writes files"
  end

  test "a manual approval step is approval gated" do
    add_step(name: "Gate", step_type: "context_fetch", manual_approval: true)
    assert_includes labels, "approval gated"
  end

  test "danger mode comes from the project" do
    @project.update!(skip_permissions: true)
    add_step(name: "Ship", step_type: "pr", config: { "title" => "x" })

    result = WorkflowAccessSummary.for(@workflow.reload)
    assert_equal "danger mode", result.first.label
    assert_includes result.map(&:label), "opens PRs"
  end

  test "chips name the steps that put them there" do
    add_step(name: "Ship it", step_type: "pr", config: { "title" => "x" })
    chip = WorkflowAccessSummary.for(@workflow.reload).find { |c| c.label == "opens PRs" }
    assert_equal "Ship it", chip.title
  end
end
