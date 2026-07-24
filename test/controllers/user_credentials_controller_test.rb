require "test_helper"

class UserCredentialsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "POST create stores a connection for the current user" do
    assert_difference "UserCredential.count", 1 do
      post user_credentials_path, params: { kind: "github_token", value: "ghp_abc" }
    end

    credential = UserCredential.last
    assert_equal users(:admin), credential.user
    assert_equal "ghp_abc", credential.value
    assert_redirected_to account_path
  end

  test "POST create replaces an existing connection of the same kind" do
    users(:admin).user_credentials.create!(kind: "github_token", value: "old")

    assert_no_difference "UserCredential.count" do
      post user_credentials_path, params: { kind: "github_token", value: "new" }
    end
    assert_equal "new", users(:admin).user_credentials.find_by(kind: "github_token").value
  end

  test "POST create refuses an unknown kind" do
    assert_no_difference "UserCredential.count" do
      post user_credentials_path, params: { kind: "aws_secret", value: "x" }
    end
    assert_match(/Unknown connection/, flash[:alert])
  end

  test "POST create refuses a blank value" do
    assert_no_difference "UserCredential.count" do
      post user_credentials_path, params: { kind: "github_token", value: "   " }
    end
    assert_match(/blank/i, flash[:alert])
  end

  test "DELETE destroy removes the connection" do
    credential = users(:admin).user_credentials.create!(kind: "github_token", value: "x")
    assert_difference "UserCredential.count", -1 do
      delete user_credential_path(credential)
    end
  end

  test "a user cannot delete somebody else's connection" do
    theirs = users(:other).user_credentials.create!(kind: "github_token", value: "theirs")

    assert_no_difference "UserCredential.count" do
      delete user_credential_path(theirs)
    end
    assert_response :not_found
  end

  test "the account page shows connection state without the value" do
    users(:admin).user_credentials.create!(kind: "github_token", value: "ghp_super_secret")

    get account_path
    assert_response :success
    assert_match "GitHub token", response.body
    assert_match(/connected/, response.body)
    assert_no_match(/ghp_super_secret/, response.body, "the decrypted value was rendered into HTML")
  end

  test "the account page offers all three connection kinds" do
    get account_path
    assert_response :success
    UserCredential::KINDS.each do |kind|
      assert_select "input[name=kind][value=?]", kind
    end
  end

  test "the paste field never round-trips a stored value" do
    users(:admin).user_credentials.create!(kind: "github_token", value: "ghp_super_secret")

    get account_path
    assert_response :success
    assert_select "input[name=value][value]", false, "the input must not be pre-filled with the secret"
  end

  test "the connections panel survives a failed account update re-render" do
    users(:admin).user_credentials.create!(kind: "github_token", value: "ghp_abc")

    patch account_path, params: { user: { email: "" } }
    assert_response :unprocessable_content
    assert_match "Connections", response.body
  end

  test "requires authentication" do
    delete logout_path
    post user_credentials_path, params: { kind: "github_token", value: "x" }
    assert_redirected_to login_path
  end
end
