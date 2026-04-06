require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "GET setup/admin redirects when users exist" do
    get new_admin_setup_path
    assert_redirected_to root_path
  end

  test "GET setup/admin renders form when no users" do
    User.delete_all
    get new_admin_setup_path
    assert_response :success
    assert_select "h2", "Create Admin Account"
  end

  test "POST setup/admin creates admin user when no users" do
    User.delete_all
    assert_difference "User.count", 1 do
      post admin_setup_path, params: {
        user: { email: "first@test.com", password: "password", password_confirmation: "password" }
      }
    end
    user = User.last
    assert user.admin?
    assert_redirected_to root_path
  end

  test "POST setup/admin redirects when users exist" do
    post admin_setup_path, params: {
      user: { email: "new@test.com", password: "password", password_confirmation: "password" }
    }
    assert_redirected_to root_path
  end

  test "POST setup/admin with invalid data re-renders form" do
    User.delete_all
    assert_no_difference "User.count" do
      post admin_setup_path, params: {
        user: { email: "", password: "password", password_confirmation: "password" }
      }
    end
    assert_response :unprocessable_content
  end
end
