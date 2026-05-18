require "test_helper"

class SkillTest < ActiveSupport::TestCase
  test "valid shared skill (filesystem-backed)" do
    s = Skill.new(name: "new_skill", source_kind: "global", relative_path: "new_skill")
    assert s.valid?
  end

  test "valid project skill (filesystem-backed)" do
    s = Skill.new(name: "proj_skill", source_kind: "project_seneschal",
                  relative_path: "proj_skill", project: projects(:seneschal))
    assert s.valid?
  end

  test "requires name" do
    s = Skill.new(source_kind: "global", relative_path: "x")
    assert_not s.valid?
    assert_includes s.errors[:name], "can't be blank"
  end

  test "requires source_kind" do
    s = Skill.new(name: "no_src", relative_path: "no_src")
    assert_not s.valid?
    assert_includes s.errors[:source_kind], "can't be blank"
  end

  test "requires relative_path" do
    s = Skill.new(name: "no_path", source_kind: "global")
    assert_not s.valid?
    assert_includes s.errors[:relative_path], "can't be blank"
  end

  test "rejects unknown source_kind" do
    s = Skill.new(name: "bad", source_kind: "made_up", relative_path: "bad")
    assert_not s.valid?
    assert_includes s.errors[:source_kind], "is not included in the list"
  end

  test "name unique within same project" do
    s = Skill.new(name: skills(:project_skill).name, source_kind: "project_seneschal",
                  relative_path: "dup", project: projects(:seneschal))
    assert_not s.valid?
  end

  test "same name allowed across different projects" do
    s = Skill.new(name: skills(:project_skill).name, source_kind: "project_seneschal",
                  relative_path: "ok", project: projects(:other_project))
    assert s.valid?
  end

  test "shared? returns true for nil project" do
    assert skills(:shared_skill).shared?
  end

  test "shared? returns false for project skill" do
    assert_not skills(:project_skill).shared?
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

  test "for_project excludes other projects' skills" do
    other = projects(:other_project)
    scoped = Skill.for_project(other)
    assert_not_includes scoped, skills(:project_skill)
  end

  test "destroying skill nullifies steps" do
    skill = skills(:shared_skill)
    step = steps(:skill_step)
    assert_equal skill, step.skill
    skill.destroy
    assert_nil step.reload.skill_id
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
    skill = Skill.create!(name: "tmp_skill", source_kind: "global", relative_path: "tmp_skill",
                          default_json_schema: schema, default_output_variable: "x_out")
    schema.destroy
    assert_nil skill.reload.default_json_schema_id
  end
end
