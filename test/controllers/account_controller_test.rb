require "test_helper"

class AccountControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET edit renders account form" do
    get account_path
    assert_response :success
  end

  test "GET edit offers to enable 2FA when it is off" do
    get account_path
    assert_select "h2", text: "Security"
    assert_select "a[href=?]", setup_two_factor_path, text: "Enable two-factor authentication"
  end

  test "GET edit offers to disable 2FA when it is on" do
    users(:admin).update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
    get account_path
    assert_select "form[action=?]", disable_two_factor_path
    assert_select "a[href=?]", setup_two_factor_path, count: 0
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
