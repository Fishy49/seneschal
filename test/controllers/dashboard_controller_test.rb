require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index renders dashboard" do
    get root_path
    assert_response :success
    assert_select "h1", /Dashboard/i
  end

  test "redirects to login when not authenticated" do
    delete logout_path
    get root_path
    assert_redirected_to login_path
  end

  test "shows active runs" do
    get root_path
    assert_response :success
  end

  test "shows actionable tasks" do
    get root_path
    assert_response :success
  end

  test "shows projects" do
    get root_path
    assert_response :success
  end

  test "dashboard sidebar lists project groups" do
    get root_path
    assert_response :success
    assert_match "Frontend", response.body
    assert_match project_path(projects(:seneschal)), response.body
  end
end
