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

  test "sign out" do
    sign_in_as users(:admin)
    click_on "Sign Out"

    assert_text "Sign In"
    assert_current_path login_path
  end

  test "unauthenticated user redirected to login" do
    visit root_path
    assert_text "Sign In"
  end

  test "accept invite and set password" do
    user = users(:invited_user)
    visit accept_invite_path(user.invite_token)

    assert_text "Set Up Your Account"
    assert_text user.email

    fill_in "Password", with: "mynewpassword"
    fill_in "Confirm Password", with: "mynewpassword"
    click_on "Set Password & Sign In"

    assert_text "Dashboard"
    assert_current_path root_path
  end

  test "invite with mismatched passwords shows error" do
    user = users(:invited_user)
    visit accept_invite_path(user.invite_token)

    fill_in "Password", with: "password"
    fill_in "Confirm Password", with: "different"
    click_on "Set Password & Sign In"

    assert_text "doesn't match"
  end

  test "invalid invite token redirected to login" do
    visit accept_invite_path("bad-token")
    assert_text "Sign In"
  end
end
