require "test_helper"

class RunnersTest < ActiveSupport::TestCase
  test "lookup returns a ClaudeCLI instance by name" do
    assert_instance_of Runners::ClaudeCLI, Runners.lookup("claude_cli")
  end

  test "lookup returns a ClaudeSDK instance by name" do
    assert_instance_of Runners::ClaudeSDK, Runners.lookup("claude_sdk")
  end

  test "lookup accepts symbols" do
    assert_instance_of Runners::ClaudeCLI, Runners.lookup(:claude_cli)
  end

  test "lookup raises UnknownRunnerError on an unknown name" do
    assert_raises(Runners::UnknownRunnerError) { Runners.lookup("nope") }
  end

  test "default_name reads from Setting when present" do
    Setting["default_runner"] = "claude_sdk"
    assert_equal "claude_sdk", Runners.default_name
  ensure
    Setting.find_by(key: "default_runner")&.destroy
  end

  test "default_name falls back to claude_cli when unset" do
    Setting.find_by(key: "default_runner")&.destroy
    assert_equal "claude_cli", Runners.default_name
  end
end
