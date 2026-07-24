require "test_helper"

class CredentialEnvTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
  end

  test "a user with no connections gets an empty overlay" do
    assert_empty CredentialEnv.for(@user)
  end

  test "nil user gets an empty overlay" do
    assert_empty CredentialEnv.for(nil)
  end

  test "a github token becomes GH_TOKEN plus a git identity" do
    @user.user_credentials.create!(kind: "github_token", value: "ghp_abc")
    env = CredentialEnv.for(@user)

    assert_equal "ghp_abc", env["GH_TOKEN"]
    assert_equal @user.email, env["GIT_AUTHOR_EMAIL"]
    assert_equal @user.email, env["GIT_COMMITTER_EMAIL"]
    assert_equal "admin", env["GIT_AUTHOR_NAME"]
    assert_equal "admin", env["GIT_COMMITTER_NAME"]
  end

  test "an anthropic api key becomes ANTHROPIC_API_KEY" do
    @user.user_credentials.create!(kind: "anthropic_api_key", value: "sk-ant-abc")
    assert_equal({ "ANTHROPIC_API_KEY" => "sk-ant-abc" }, CredentialEnv.for(@user))
  end

  test "a claude oauth token becomes CLAUDE_CODE_OAUTH_TOKEN" do
    @user.user_credentials.create!(kind: "claude_oauth_token", value: "oat-abc")
    assert_equal({ "CLAUDE_CODE_OAUTH_TOKEN" => "oat-abc" }, CredentialEnv.for(@user))
  end

  test "the api key wins when both Claude kinds are stored" do
    @user.user_credentials.create!(kind: "anthropic_api_key", value: "sk-ant-abc")
    @user.user_credentials.create!(kind: "claude_oauth_token", value: "oat-abc")

    env = CredentialEnv.for(@user)
    assert_equal "sk-ant-abc", env["ANTHROPIC_API_KEY"]
    assert_not env.key?("CLAUDE_CODE_OAUTH_TOKEN"),
               "sending both would let the two credentials disagree about identity"
  end

  test "github and claude credentials combine" do
    @user.user_credentials.create!(kind: "github_token", value: "ghp_abc")
    @user.user_credentials.create!(kind: "anthropic_api_key", value: "sk-ant-abc")

    env = CredentialEnv.for(@user)
    assert_equal "ghp_abc", env["GH_TOKEN"]
    assert_equal "sk-ant-abc", env["ANTHROPIC_API_KEY"]
  end

  test "no git identity is set without a github token" do
    @user.user_credentials.create!(kind: "anthropic_api_key", value: "sk-ant-abc")
    assert_not CredentialEnv.for(@user).key?("GIT_AUTHOR_NAME")
  end

  test "only the given user's credentials are ever returned" do
    @user.user_credentials.create!(kind: "github_token", value: "mine")
    users(:other).user_credentials.create!(kind: "github_token", value: "theirs")

    assert_equal "mine", CredentialEnv.for(@user)["GH_TOKEN"]
    assert_equal "theirs", CredentialEnv.for(users(:other))["GH_TOKEN"]
  end
end
