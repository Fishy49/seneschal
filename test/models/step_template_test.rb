require "test_helper"

class StepTemplateTest < ActiveSupport::TestCase
  test "valid skill template" do
    t = StepTemplate.new(name: "New Template", step_type: "skill", skill: skills(:shared_skill))
    assert t.valid?
  end

  test "valid command template" do
    t = StepTemplate.new(name: "Cmd Template", step_type: "command", body: "echo hello")
    assert t.valid?
  end

  test "requires name" do
    t = StepTemplate.new(step_type: "command", body: "echo")
    assert_not t.valid?
    assert_includes t.errors[:name], "can't be blank"
  end

  test "requires unique name" do
    t = StepTemplate.new(name: step_templates(:skill_template).name, step_type: "command", body: "echo")
    assert_not t.valid?
    assert_includes t.errors[:name], "has already been taken"
  end

  test "requires step_type" do
    t = StepTemplate.new(name: "X")
    assert_not t.valid?
    assert_includes t.errors[:step_type], "is not included in the list"
  end

  test "requires skill for skill type" do
    t = StepTemplate.new(name: "X", step_type: "skill")
    assert_not t.valid?
    assert_includes t.errors[:skill], "can't be blank"
  end

  test "requires body for command type" do
    t = StepTemplate.new(name: "X", step_type: "command")
    assert_not t.valid?
    assert_includes t.errors[:body], "can't be blank"
  end

  test "requires body for script type" do
    t = StepTemplate.new(name: "X", step_type: "script")
    assert_not t.valid?
    assert_includes t.errors[:body], "can't be blank"
  end

  test "ci_check does not require body or skill" do
    t = StepTemplate.new(name: "X", step_type: "ci_check")
    assert t.valid?
  end

  test "template_data returns serializable hash" do
    t = step_templates(:command_template)
    data = t.template_data
    assert_equal "command", data[:step_type]
    assert_equal "git checkout main && git pull", data[:body]
    assert_equal 120, data[:timeout]
  end

  test "ordered scope sorts by name" do
    names = StepTemplate.ordered.pluck(:name)
    assert_equal names.sort, names
  end
end
