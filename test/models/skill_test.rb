require "test_helper"

class SkillTest < ActiveSupport::TestCase
  test "valid shared skill" do
    s = Skill.new(name: "new_skill", body: "Do something")
    assert s.valid?
  end

  test "valid project skill" do
    s = Skill.new(name: "proj_skill", body: "Do something", project: projects(:seneschal))
    assert s.valid?
  end

  test "requires name" do
    s = Skill.new(body: "Do something")
    assert_not s.valid?
    assert_includes s.errors[:name], "can't be blank"
  end

  test "requires body" do
    s = Skill.new(name: "no_body")
    assert_not s.valid?
    assert_includes s.errors[:body], "can't be blank"
  end

  test "name unique within same project" do
    s = Skill.new(name: skills(:project_skill).name, body: "Dup", project: projects(:seneschal))
    assert_not s.valid?
  end

  test "same name allowed across different projects" do
    s = Skill.new(name: skills(:project_skill).name, body: "OK", project: projects(:other_project))
    assert s.valid?
  end

  test "shared? returns true for nil project" do
    assert skills(:shared_skill).shared?
  end

  test "shared? returns false for project skill" do
    assert_not skills(:project_skill).shared?
  end

  test "display_name for shared skill" do
    assert_equal "ingest_feature", skills(:shared_skill).display_name
  end

  test "display_name for project skill" do
    skill = skills(:project_skill)
    assert_equal "Seneschal/deploy_check", skill.display_name
  end

  test "shared scope returns only shared skills" do
    shared = Skill.shared
    shared.each { |s| assert_nil s.project_id }
  end

  test "for_project scope returns shared and project skills" do
    project = projects(:seneschal)
    scoped = Skill.for_project(project)
    assert_includes scoped, skills(:shared_skill)
    assert_includes scoped, skills(:project_skill)
  end

  test "destroying skill nullifies steps" do
    skill = skills(:shared_skill)
    step = steps(:skill_step)
    assert_equal skill, step.skill
    skill.destroy
    assert_nil step.reload.skill_id
  end
end
