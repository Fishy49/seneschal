require "test_helper"

class AccountControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET edit renders account form" do
    get account_path
    assert_response :success
  end

  test "PATCH update email" do
    patch account_path, params: { user: { email: "newemail@test.com" } }
    assert_redirected_to account_path
    assert_equal "newemail@test.com", users(:admin).reload.email
  end

  test "PATCH update password" do
    patch account_path, params: {
      user: { password: "newpassword", password_confirmation: "newpassword" }
    }
    assert_redirected_to account_path
    assert users(:admin).reload.authenticate("newpassword")
  end

  test "PATCH update with blank password keeps existing" do
    patch account_path, params: { user: { email: "keep@test.com", password: "", password_confirmation: "" } }
    assert_redirected_to account_path
    assert users(:admin).reload.authenticate("password")
  end

  test "PATCH update with invalid email" do
    patch account_path, params: { user: { email: "invalid" } }
    assert_response :unprocessable_content
  end

  test "works without setup complete" do
    Setting.destroy_all
    get account_path
    assert_response :success
  end
end
