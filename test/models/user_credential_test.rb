require "test_helper"

class UserCredentialTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
  end

  test "stores and round-trips a value" do
    credential = @user.user_credentials.create!(kind: "github_token", value: "ghp_secret_token")
    assert_equal "ghp_secret_token", credential.reload.value
  end

  test "the value is encrypted at rest" do
    @user.user_credentials.create!(kind: "github_token", value: "ghp_secret_token")

    raw = UserCredential.connection.select_value(
      "SELECT value FROM user_credentials WHERE user_id = #{@user.id}"
    )
    assert_no_match(/ghp_secret_token/, raw, "the token is sitting in the database in plaintext")
    assert_match(/\A\{/, raw, "expected an Active Record encryption envelope")
  end

  test "rejects an unknown kind" do
    credential = @user.user_credentials.build(kind: "aws_key", value: "x")
    assert_not credential.valid?
    assert_includes credential.errors[:kind], "is not included in the list"
  end

  test "requires a value" do
    assert_not @user.user_credentials.build(kind: "github_token", value: "  ").valid?
  end

  test "one credential per kind per user" do
    @user.user_credentials.create!(kind: "github_token", value: "a")
    duplicate = @user.user_credentials.build(kind: "github_token", value: "b")
    assert_not duplicate.valid?
  end

  test "different users may each hold the same kind" do
    @user.user_credentials.create!(kind: "github_token", value: "a")
    assert users(:other).user_credentials.build(kind: "github_token", value: "b").valid?
  end

  test "surrounding whitespace is stripped from a pasted value" do
    credential = @user.user_credentials.create!(kind: "github_token", value: "  ghp_padded\n")
    assert_equal "ghp_padded", credential.value
  end

  test "masked never contains the value" do
    credential = @user.user_credentials.create!(kind: "github_token", value: "ghp_secret_token")
    assert_no_match(/ghp/, credential.masked)
    assert_no_match(/secret/, credential.masked)
    assert_match(/16 characters/, credential.masked)
  end

  test "deleting the user deletes their credentials" do
    user = User.create!(email: "temp-cred@test.com", password: "password12")
    user.user_credentials.create!(kind: "github_token", value: "x")

    assert_difference "UserCredential.count", -1 do
      user.destroy!
    end
  end
end
