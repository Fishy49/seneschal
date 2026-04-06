require "test_helper"

class InvitesControllerTest < ActionDispatch::IntegrationTest
  test "GET invite with valid token renders form" do
    get accept_invite_path(users(:invited_user).invite_token)
    assert_response :success
    assert_select "h2", "Set Up Your Account"
  end

  test "GET invite with invalid token redirects to login" do
    get accept_invite_path("bogus-token")
    assert_redirected_to login_path
  end

  test "PATCH invite sets password and signs in" do
    user = users(:invited_user)
    patch accept_invite_path(user.invite_token), params: {
      user: { password: "newpassword", password_confirmation: "newpassword" }
    }
    assert_redirected_to root_path
    user.reload
    assert_nil user.invite_token
    assert_not_nil user.invite_accepted_at
    assert user.authenticate("newpassword")
  end

  test "PATCH invite with mismatched passwords re-renders" do
    user = users(:invited_user)
    patch accept_invite_path(user.invite_token), params: {
      user: { password: "newpassword", password_confirmation: "different" }
    }
    assert_response :unprocessable_content
    assert_not_nil user.reload.invite_token
  end

  test "PATCH invite with blank password re-renders" do
    user = users(:invited_user)
    patch accept_invite_path(user.invite_token), params: {
      user: { password: "", password_confirmation: "" }
    }
    assert_response :unprocessable_content
    assert_not_nil user.reload.invite_token
  end
end
