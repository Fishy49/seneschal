require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "GET login renders sign in form" do
    get login_path
    assert_response :success
    assert_select "h2", "Sign In"
  end

  test "POST login with valid credentials" do
    post login_path, params: { email: users(:admin).email, password: "password" }
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
  end

  test "POST login with wrong password" do
    post login_path, params: { email: users(:admin).email, password: "wrong" }
    assert_response :unprocessable_content
    assert_select "h2", "Sign In"
  end

  test "POST login with nonexistent email" do
    post login_path, params: { email: "nobody@test.com", password: "password" }
    assert_response :unprocessable_content
  end

  test "POST login with 2FA redirects to 2FA page" do
    post login_path, params: { email: users(:twofa_user).email, password: "password" }
    assert_redirected_to two_factor_path
  end

  test "DELETE logout clears session" do
    sign_in users(:admin)
    delete logout_path
    assert_redirected_to login_path
    # Verify we're logged out
    get root_path
    assert_redirected_to login_path
  end
end
