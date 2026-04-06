require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index lists users" do
    get users_path
    assert_response :success
    assert_select "td", text: users(:admin).email
    assert_select "td", text: users(:other).email
  end

  test "GET index requires admin" do
    sign_out
    sign_in users(:other)
    get users_path
    assert_redirected_to root_path
  end

  test "GET new renders form" do
    get new_user_path
    assert_response :success
    assert_select "h1", "New User"
  end

  test "POST create creates user with invite token" do
    assert_difference "User.count", 1 do
      post users_path, params: { user: { email: "newmember@test.com" } }
    end
    user = User.find_by(email: "newmember@test.com")
    assert_not_nil user.invite_token
    assert_not user.admin?
    assert_redirected_to users_path
  end

  test "POST create with admin flag" do
    post users_path, params: { user: { email: "newadmin@test.com", admin: true } }
    user = User.find_by(email: "newadmin@test.com")
    assert user.admin?
  end

  test "POST create with duplicate email fails" do
    assert_no_difference "User.count" do
      post users_path, params: { user: { email: users(:admin).email } }
    end
    assert_response :unprocessable_content
  end

  test "DELETE destroy removes user" do
    assert_difference "User.count", -1 do
      delete user_path(users(:other))
    end
    assert_redirected_to users_path
  end

  test "DELETE destroy prevents self-deletion" do
    assert_no_difference "User.count" do
      delete user_path(users(:admin))
    end
    assert_redirected_to users_path
    follow_redirect!
    assert_select ".bg-danger\\/15", /cannot delete/i
  end

  test "POST reset_invite regenerates token" do
    user = users(:invited_user)
    old_token = user.invite_token
    post reset_invite_user_path(user)
    assert_not_equal old_token, user.reload.invite_token
    assert_redirected_to users_path
  end

  test "non-admin cannot access user management" do
    sign_out
    sign_in users(:other)
    get users_path
    assert_redirected_to root_path
    post users_path, params: { user: { email: "x@test.com" } }
    assert_redirected_to root_path
  end
end
