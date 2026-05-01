require "test_helper"

class SkillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index lists skills" do
    get skills_path
    assert_response :success
  end

  test "GET index displays group section with group name and skill" do
    get skills_path
    assert_response :success
    assert_match "Frontend", response.body
    assert_match "lint_check", response.body
  end

  test "GET index filters by group_id" do
    get skills_path, params: { group_id: project_groups(:frontend).id }
    assert_response :success
    assert_match skills(:group_skill).name, response.body
    assert_no_match skills(:shared_skill).name, response.body
  end

  test "GET show displays skill" do
    get skill_path(skills(:shared_skill))
    assert_response :success
  end

  test "GET show displays group designation for group skill" do
    get skill_path(skills(:group_skill))
    assert_response :success
    assert_match "Group: Frontend", response.body
  end

  test "GET new renders form" do
    get new_skill_path
    assert_response :success
  end

  test "POST create shared skill" do
    assert_difference "Skill.count", 1 do
      post skills_path, params: {
        skill: { name: "new_skill", body: "Do the thing", description: "A skill" }
      }
    end
    assert_redirected_to skill_path(Skill.last)
    assert_nil Skill.last.project_id
  end

  test "POST create project skill" do
    assert_difference "Skill.count", 1 do
      post skills_path, params: {
        skill: { name: "proj_new", body: "Do the thing", scope: "project:#{projects(:seneschal).id}" }
      }
    end
    assert_redirected_to skill_path(Skill.last)
    assert_equal projects(:seneschal).id, Skill.last.project_id
    assert_nil Skill.last.project_group_id
  end

  test "POST create group skill" do
    assert_difference "Skill.count", 1 do
      post skills_path, params: {
        skill: { name: "lint", body: "Run lint", scope: "group:#{project_groups(:frontend).id}" }
      }
    end
    assert_redirected_to skill_path(Skill.last)
    assert_equal project_groups(:frontend).id, Skill.last.project_group_id
    assert_nil Skill.last.project_id
  end

  test "POST create with invalid params" do
    assert_no_difference "Skill.count" do
      post skills_path, params: { skill: { name: "", body: "" } }
    end
    assert_response :unprocessable_content
  end

  test "GET edit renders form" do
    get edit_skill_path(skills(:shared_skill))
    assert_response :success
  end

  test "GET edit pre-selects group scope" do
    get edit_skill_path(skills(:group_skill))
    assert_response :success
    assert_select "option[selected][value=?]", "group:#{project_groups(:frontend).id}"
  end

  test "PATCH update" do
    patch skill_path(skills(:shared_skill)), params: {
      skill: { description: "Updated description" }
    }
    assert_redirected_to skill_path(skills(:shared_skill))
  end

  test "PATCH update reassigns from project to group" do
    patch skill_path(skills(:project_skill)), params: {
      skill: { scope: "group:#{project_groups(:frontend).id}" }
    }
    assert_redirected_to skill_path(skills(:project_skill))
    skill = skills(:project_skill).reload
    assert_nil skill.project_id
    assert_equal project_groups(:frontend).id, skill.project_group_id
  end

  test "PATCH update reassigns from group to shared" do
    patch skill_path(skills(:group_skill)), params: {
      skill: { scope: "" }
    }
    skill = skills(:group_skill).reload
    assert_nil skill.project_id
    assert_nil skill.project_group_id
    assert skill.shared?
  end

  test "PATCH update without scope param preserves existing scope" do
    skill = skills(:group_skill)
    patch skill_path(skill), params: {
      skill: { description: "Updated description" }
    }
    skill.reload
    assert_equal "Updated description", skill.description
    assert_equal project_groups(:frontend).id, skill.project_group_id
    assert_nil skill.project_id
  end

  test "DELETE destroy" do
    skill = Skill.create!(name: "disposable", body: "temp")
    assert_difference "Skill.count", -1 do
      delete skill_path(skill)
    end
    assert_redirected_to skills_path
  end
end
