require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  test "valid workflow" do
    w = Workflow.new(name: "New Workflow", project: projects(:seneschal), trigger_type: "manual")
    assert w.valid?
  end

  test "requires name" do
    w = Workflow.new(project: projects(:seneschal), trigger_type: "manual")
    assert_not w.valid?
    assert_includes w.errors[:name], "can't be blank"
  end

  test "requires unique name per project" do
    w = Workflow.new(
      name: workflows(:deploy).name,
      project: projects(:seneschal),
      trigger_type: "manual"
    )
    assert_not w.valid?
  end

  test "allows same name in different projects" do
    w = Workflow.new(
      name: workflows(:deploy).name,
      project: projects(:other_project),
      trigger_type: "manual"
    )
    assert w.valid?
  end

  test "validates trigger_type inclusion" do
    w = Workflow.new(name: "Bad", project: projects(:seneschal), trigger_type: "invalid")
    assert_not w.valid?
  end

  test "accepts all valid trigger types" do
    ["manual", "cron", "file_watch"].each do |tt|
      w = Workflow.new(name: "TT-#{tt}", project: projects(:seneschal), trigger_type: tt)
      assert w.valid?, "Expected #{tt} to be valid"
    end
  end

  test "has_many steps ordered by position" do
    workflow = workflows(:deploy)
    positions = workflow.steps.pluck(:position)
    assert_equal positions.sort, positions
  end

  test "destroying workflow destroys steps" do
    workflow = projects(:other_project).workflows.create!(name: "Disposable", trigger_type: "manual")
    workflow.steps.create!(name: "s1", step_type: "command", body: "echo 1", position: 1)
    workflow.steps.create!(name: "s2", step_type: "command", body: "echo 2", position: 2)
    assert_difference "Step.count", -2 do
      workflow.destroy
    end
  end
end
