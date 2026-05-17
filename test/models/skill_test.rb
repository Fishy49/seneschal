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

  test "valid group skill" do
    s = Skill.new(name: "g_skill", body: "do", project_group: project_groups(:frontend))
    assert s.valid?
    assert_equal project_groups(:frontend).id, s.project_group_id
    assert_not s.shared?
    assert s.group_scoped?
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

  test "scope is exclusive: cannot have both project and group" do
    s = Skill.new(name: "x", body: "y", project: projects(:seneschal), project_group: project_groups(:frontend))
    assert_not s.valid?
    assert_includes s.errors[:base], "Skill cannot belong to both a project and a project group"
  end

  test "shared? returns true for nil project" do
    assert skills(:shared_skill).shared?
  end

  test "shared? returns false for project skill" do
    assert_not skills(:project_skill).shared?
  end

  test "shared? returns false for group skill" do
    assert_not skills(:group_skill).shared?
  end

  test "group_scoped? returns true for group skill" do
    assert skills(:group_skill).group_scoped?
  end

  test "group_scoped? returns false for shared skill" do
    assert_not skills(:shared_skill).group_scoped?
  end

  test "project_scoped? returns true for project skill" do
    assert skills(:project_skill).project_scoped?
  end

  test "display_name for shared skill" do
    assert_equal "ingest_feature", skills(:shared_skill).display_name
  end

  test "display_name for project skill" do
    skill = skills(:project_skill)
    assert_equal "Seneschal/deploy_check", skill.display_name
  end

  test "display_name for group skill" do
    skill = skills(:group_skill)
    assert_equal "Frontend/lint_check", skill.display_name
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

  test "for_project includes group skills when project belongs to the group" do
    project = projects(:seneschal)
    scoped = Skill.for_project(project)
    assert_includes scoped, skills(:shared_skill)
    assert_includes scoped, skills(:project_skill)
    assert_includes scoped, skills(:group_skill)

    backend_skill = Skill.create!(name: "backend_lint", body: "x", project_group: project_groups(:backend))
    assert_not_includes Skill.for_project(project), backend_skill
  end

  test "for_project excludes group skills when project has no group" do
    project = projects(:other_project)
    scoped = Skill.for_project(project)
    assert_not_includes scoped, skills(:group_skill)
  end

  test "destroying skill nullifies steps" do
    skill = skills(:shared_skill)
    step = steps(:skill_step)
    assert_equal skill, step.skill
    skill.destroy
    assert_nil step.reload.skill_id
  end

  test "destroying a project_group nilifies project_group_id on its skills" do
    skill = skills(:group_skill)
    assert_not_nil skill.project_group_id
    project_groups(:frontend).destroy
    assert_nil skill.reload.project_group_id
  end

  # --- Default schema + output variable ---

  test "default_output_variable must be snake_case when set" do
    skill = skills(:shared_skill)
    skill.default_output_variable = "MyOutput"
    assert_not skill.valid?
    assert_includes skill.errors[:default_output_variable].first, "snake_case"
  end

  test "default_output_variable accepts blank when no schema is set" do
    skill = skills(:shared_skill)
    skill.default_json_schema = nil
    skill.default_output_variable = nil
    assert skill.valid?
  end

  test "default_output_variable required when default schema is set" do
    skill = skills(:shared_skill)
    skill.default_json_schema = json_schemas(:simple_schema)
    skill.default_output_variable = nil
    assert_not skill.valid?
    assert_includes skill.errors[:default_output_variable].first, "required"
  end

  test "default schema + output variable are persisted and round-trip" do
    skill = skills(:shared_skill)
    skill.update!(
      default_json_schema: json_schemas(:simple_schema),
      default_output_variable: "feature_plan"
    )
    skill.reload
    assert_equal json_schemas(:simple_schema), skill.default_json_schema
    assert_equal "feature_plan", skill.default_output_variable
  end

  test "destroying the default schema nullifies the link on associated skills" do
    schema = JsonSchema.create!(name: "tmp_default", body: '{"type":"object"}')
    skill = Skill.create!(name: "tmp_skill", body: "x",
                          default_json_schema: schema, default_output_variable: "x_out")
    schema.destroy
    assert_nil skill.reload.default_json_schema_id
  end
end
