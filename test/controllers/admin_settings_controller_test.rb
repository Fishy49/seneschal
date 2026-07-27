require "test_helper"

class AdminSettingsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:admin) }

  test "GET show renders every section" do
    get admin_settings_path
    assert_response :success
    assert_select "select#default_runner"
    assert_select "input#default_allowed_tools"
    assert_select "textarea#skills_global_roots"
    assert_select "input#worktree_retention_days"
    assert_select "input#python_bin"
    assert_select "textarea#mcp_servers"
    assert_select "input#webhook_url"
  end

  test "members are turned away" do
    sign_in users(:other)
    get admin_settings_path
    assert_response :redirect
  end

  test "PATCH update saves the execution defaults" do
    patch admin_settings_path, params: {
      default_runner: "claude_sdk", default_allowed_tools: " Bash,Read ", confine_writes_to_cwd: "false"
    }
    assert_redirected_to admin_settings_path
    assert_equal "claude_sdk", Setting["default_runner"]
    assert_equal "claude_sdk", Runners.default_name
    assert_equal "Bash,Read", Setting["default_allowed_tools"]
    assert_equal "false", Setting["confine_writes_to_cwd"]
  end

  test "PATCH update ignores an unknown engine" do
    Setting["default_runner"] = "claude_cli"
    patch admin_settings_path, params: { default_runner: "nonsense" }
    assert_equal "claude_cli", Setting["default_runner"]
  end

  test "PATCH update records the confinement checkbox when ticked" do
    patch admin_settings_path, params: { confine_writes_to_cwd: "true" }
    assert_equal "true", Setting["confine_writes_to_cwd"]
  end

  test "PATCH update saves the paths" do
    patch admin_settings_path, params: {
      skills_global_roots: "/one\n/two", skill_repo_root: "/repos",
      worktree_root: "/wt", worktree_retention_days: "9", run_assets_root: "/assets"
    }
    assert_equal "/one\n/two", Setting["skills_global_roots"]
    assert_equal "/repos", Setting["skill_repo_root"]
    assert_equal "/wt", WorktreeManager.worktree_root
    assert_equal 9, WorktreeManager.retention_days
    assert_equal "/assets", Setting["run_assets_root"]
  end

  test "PATCH update saves the sidecar and notification keys" do
    patch admin_settings_path, params: {
      python_bin: "/usr/bin/python3", sdk_runner_script: "/opt/runner.py",
      webhook_url: "https://example.com/hook", slack_webhook_url: "https://hooks.slack.com/x",
      app_base_url: "https://seneschal.internal"
    }
    assert_equal "/usr/bin/python3", Setting["python_bin"]
    assert_equal "/opt/runner.py", Setting["sdk_runner_script"]
    assert_equal "https://example.com/hook", Setting["webhook_url"]
    assert_equal "https://hooks.slack.com/x", Setting["slack_webhook_url"]
    assert_equal "https://seneschal.internal", Setting["app_base_url"]
  end

  test "a blank value clears the key so its default comes back" do
    Setting["worktree_root"] = "/wt"
    patch admin_settings_path, params: { worktree_root: "  " }
    assert_nil Setting["worktree_root"]
  end

  test "PATCH update saves valid MCP JSON" do
    patch admin_settings_path, params: { mcp_servers: '{"files":{"command":"mcp-files"}}' }
    assert_redirected_to admin_settings_path
    assert_equal '{"files":{"command":"mcp-files"}}', Setting["mcp_servers"]
  end

  test "PATCH update rejects malformed MCP JSON without saving anything" do
    Setting["worktree_root"] = "/keep"
    patch admin_settings_path, params: { mcp_servers: "{not json", worktree_root: "/changed" }
    assert_response :unprocessable_content
    assert_nil Setting["mcp_servers"]
    assert_equal "/keep", Setting["worktree_root"]
  end

  test "PATCH update rejects MCP JSON that is not an object" do
    patch admin_settings_path, params: { mcp_servers: "[1,2]" }
    assert_response :unprocessable_content
    assert_nil Setting["mcp_servers"]
  end

  test "PATCH update rejects a non-positive retention" do
    patch admin_settings_path, params: { worktree_retention_days: "0" }
    assert_response :unprocessable_content
    assert_nil Setting["worktree_retention_days"]

    patch admin_settings_path, params: { worktree_retention_days: "seven" }
    assert_response :unprocessable_content
    assert_nil Setting["worktree_retention_days"]
  end

  test "the health checks render alongside the forms" do
    get admin_settings_path
    assert_select "form[action=?]", check_claude_setup_path
    assert_select "form[action=?]", check_gh_setup_path
  end
end
