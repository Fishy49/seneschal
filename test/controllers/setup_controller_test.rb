require "test_helper"

class SetupControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index renders setup page" do
    get setup_path
    assert_response :success
  end

  test "GET index works without settings" do
    Setting.destroy_all
    get setup_path
    assert_response :success
  end

  test "PATCH update_allowed_tools saves setting" do
    patch update_allowed_tools_setup_path, params: { default_allowed_tools: "Bash,Read,Edit" }
    assert_redirected_to setup_path
    assert_equal "Bash,Read,Edit", Setting["default_allowed_tools"]
  end

  test "works without setup complete" do
    Setting.destroy_all
    get setup_path
    assert_response :success
  end

  test "POST check_sdk_runner records the import version on success" do
    with_stubbed_capture2e(success: true, output: "0.2.82") do
      post check_sdk_runner_setup_path
    end
    assert_redirected_to setup_path
    assert_equal "claude-agent-sdk 0.2.82 (python3)", strip_python_path(Setting["sdk_runner"])
    assert Setting["sdk_runner_checked_at"].present?
  ensure
    Setting.where(key: ["sdk_runner", "sdk_runner_checked_at"]).destroy_all
  end

  test "POST check_sdk_runner clears the setting on failure" do
    Setting["sdk_runner"] = "stale"
    Setting["sdk_runner_checked_at"] = Time.current.iso8601
    with_stubbed_capture2e(success: false, output: "ModuleNotFoundError: No module named 'claude_agent_sdk'") do
      post check_sdk_runner_setup_path
    end
    assert_redirected_to setup_path
    assert_nil Setting["sdk_runner"]
    assert_nil Setting["sdk_runner_checked_at"]
  end

  private

  # Same alias_method shim pattern the rest of the suite uses to stub
  # Open3 calls without dragging Mocha into the Gemfile. Restores the
  # original method on yield exit even when the test raises.
  def with_stubbed_capture2e(success:, output:)
    mc = Open3.singleton_class
    mc.send(:alias_method, :__orig_capture2e, :capture2e)
    status = Object.new
    status.define_singleton_method(:success?) { success }
    mc.send(:define_method, :capture2e) { |*_argv| [output, status] }
    yield
  ensure
    mc.send(:remove_method, :capture2e)
    mc.send(:alias_method, :capture2e, :__orig_capture2e)
    mc.send(:remove_method, :__orig_capture2e)
  end

  # The python_bin component of the recorded string varies per machine
  # (system python3 vs bundled venv); normalize for assertion.
  def strip_python_path(value)
    value.to_s.sub(/\((?:[^)]*)\)\z/, "(python3)")
  end
end
