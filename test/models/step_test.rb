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
end
