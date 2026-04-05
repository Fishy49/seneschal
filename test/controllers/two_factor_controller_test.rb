require "test_helper"

class TwoFactorControllerTest < ActionDispatch::IntegrationTest
  test "GET new without pending user redirects to login" do
    get new_two_factor_path
    assert_redirected_to login_path
  end

  test "GET new with pending user renders form" do
    post login_path, params: { email: users(:twofa_user).email, password: "password" }
    get new_two_factor_path
    assert_response :success
  end

  test "POST create with valid code logs in" do
    user = users(:twofa_user)
    post login_path, params: { email: user.email, password: "password" }

    totp = ROTP::TOTP.new(user.otp_secret)
    post two_factor_path, params: { code: totp.now }
    assert_redirected_to root_path
  end

  test "POST create with invalid code rejects" do
    user = users(:twofa_user)
    post login_path, params: { email: user.email, password: "password" }

    post two_factor_path, params: { code: "000000" }
    assert_response :unprocessable_content
  end

  test "GET setup renders QR code" do
    sign_in users(:admin)
    get setup_two_factor_path
    assert_response :success
  end

  test "POST confirm with valid code enables 2FA" do
    user = users(:admin)
    sign_in user
    user.generate_otp_secret!

    totp = ROTP::TOTP.new(user.reload.otp_secret)
    post confirm_two_factor_path, params: { code: totp.now }
    assert_redirected_to root_path
    assert user.reload.otp_required_for_login
  end

  test "POST disable turns off 2FA" do
    # Sign in directly (bypass 2FA redirect by setting session manually)
    user = users(:admin)
    user.generate_otp_secret!
    user.enable_2fa!
    sign_in user
    # Complete 2FA
    totp = ROTP::TOTP.new(user.reload.otp_secret)
    post two_factor_path, params: { code: totp.now }
    follow_redirect!

    post disable_two_factor_path
    assert_redirected_to root_path
    assert_not user.reload.otp_required_for_login
  end
end
