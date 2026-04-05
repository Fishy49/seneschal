require "application_system_test_case"

class AuthenticationTest < ApplicationSystemTestCase
  test "sign in with valid credentials" do
    visit login_path
    fill_in "Email", with: users(:admin).email
    fill_in "Password", with: "password"
    click_on "Sign In"

    assert_text "Dashboard"
    assert_current_path root_path
  end

  test "sign in with invalid credentials shows error" do
    visit login_path
    fill_in "Email", with: users(:admin).email
    fill_in "Password", with: "wrong"
    click_on "Sign In"

    assert_text "Invalid email or password"
    assert_current_path login_path
  end

  test "register new account" do
    visit register_path
    fill_in "Email", with: "newuser@test.com"
    fill_in "Password", with: "securepassword"
    fill_in "Confirm Password", with: "securepassword"
    click_on "Create Account"

    assert_text "Dashboard"
    assert_current_path root_path
  end

  test "register with mismatched passwords shows errors" do
    visit register_path
    fill_in "Email", with: "newuser@test.com"
    fill_in "Password", with: "password"
    fill_in "Confirm Password", with: "different"
    click_on "Create Account"

    assert_text "doesn't match"
  end

  test "sign out" do
    sign_in_as users(:admin)
    click_on "Sign Out"

    assert_text "Sign In"
    assert_current_path login_path
  end

  test "navigate from login to register" do
    visit login_path
    click_on "Register"

    assert_text "Create Account"
  end

  test "navigate from register to login" do
    visit register_path
    click_on "Sign in"

    assert_text "Sign In"
  end

  test "unauthenticated user redirected to login" do
    visit root_path
    assert_text "Sign In"
  end
end
