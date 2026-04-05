require "test_helper"

class SkillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index lists skills" do
    get skills_path
    assert_response :success
  end

  test "GET show displays skill" do
    get skill_path(skills(:shared_skill))
    assert_response :success
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
        skill: { name: "proj_new", body: "Do the thing", project_id: projects(:seneschal).id }
      }
    end
    assert_redirected_to skill_path(Skill.last)
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

  test "PATCH update" do
    patch skill_path(skills(:shared_skill)), params: {
      skill: { description: "Updated description" }
    }
    assert_redirected_to skill_path(skills(:shared_skill))
  end

  test "DELETE destroy" do
    skill = Skill.create!(name: "disposable", body: "temp")
    assert_difference "Skill.count", -1 do
      delete skill_path(skill)
    end
    assert_redirected_to skills_path
  end
end
