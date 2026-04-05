require "test_helper"

class SetupControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index renders setup page" do
    get setup_path
    assert_response :success
  end

  test "GET index works without settings" do
    Setting.destroy_all
    get setup_path
    assert_response :success
  end

  test "PATCH update_allowed_tools saves setting" do
    patch update_allowed_tools_setup_path, params: { default_allowed_tools: "Bash,Read,Edit" }
    assert_redirected_to setup_path
    assert_equal "Bash,Read,Edit", Setting["default_allowed_tools"]
  end

  test "works without setup complete" do
    Setting.destroy_all
    get setup_path
    assert_response :success
  end
end
