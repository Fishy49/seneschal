require "test_helper"

class ProjectGroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index lists groups" do
    get project_groups_path
    assert_response :success
    assert_match "Frontend", response.body
  end

  test "GET new renders form" do
    get new_project_group_path
    assert_response :success
  end

  test "POST create with valid params creates group" do
    assert_difference "ProjectGroup.count", 1 do
      post project_groups_path, params: { project_group: { name: "QA" } }
    end
    assert_redirected_to project_groups_path
  end

  test "POST create with invalid params re-renders new" do
    assert_no_difference "ProjectGroup.count" do
      post project_groups_path, params: { project_group: { name: "" } }
    end
    assert_response :unprocessable_content
  end

  test "GET edit renders form" do
    get edit_project_group_path(project_groups(:frontend))
    assert_response :success
  end

  test "PATCH update renames group and propagates" do
    projects(:seneschal).update!(project_group: project_groups(:frontend))
    patch project_group_path(project_groups(:frontend)), params: { project_group: { name: "UI" } }
    assert_redirected_to project_groups_path
    assert_equal "UI", project_groups(:frontend).reload.name
    assert_equal "UI", projects(:seneschal).reload.project_group.name
  end

  test "DELETE destroy removes group" do
    assert_difference "ProjectGroup.count", -1 do
      delete project_group_path(project_groups(:backend))
    end
    assert_redirected_to project_groups_path
  end

  test "requires authentication" do
    delete logout_path
    get project_groups_path
    assert_redirected_to login_path
  end
end
