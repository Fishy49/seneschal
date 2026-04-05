require "open3"

class SetupController < ApplicationController
  skip_before_action :require_setup

  def index
    @claude = integration_status("claude_cli")
    @gh = integration_status("gh_cli")
    @allowed_tools = Setting["default_allowed_tools"].presence || StepExecutor::DEFAULT_ALLOWED_TOOLS
    @all_ok = @claude[:ok] && @gh[:ok]
  end

  def update_allowed_tools
    Setting["default_allowed_tools"] = params[:default_allowed_tools].strip
    redirect_to setup_path, notice: "Allowed tools updated."
  end

  def check_claude
    result = run_check("claude --version")
    if result[:success]
      Setting["claude_cli"] = result[:output]
      Setting["claude_cli_checked_at"] = Time.current.iso8601
      flash[:notice] = "Claude CLI verified."
    else
      clear_keys("claude_cli")
      flash[:alert] = "Claude CLI check failed: #{result[:output]}"
    end
    redirect_to setup_path
  end

  def check_gh
    result = run_check("gh auth status 2>&1")
    if result[:success]
      Setting["gh_cli"] = result[:output]
      Setting["gh_cli_checked_at"] = Time.current.iso8601
      flash[:notice] = "GitHub CLI verified."
    else
      clear_keys("gh_cli")
      flash[:alert] = "GitHub CLI check failed: #{result[:output]}"
    end
    redirect_to setup_path
  end

  private

  def integration_status(key)
    value = Setting[key]
    checked_at = Setting["#{key}_checked_at"]
    if value.present? && checked_at.present?
      { ok: true, details: value, checked_at: Time.iso8601(checked_at) }
    else
      { ok: false }
    end
  end

  def run_check(cmd)
    Timeout.timeout(15) do
      output, status = Open3.capture2e(cmd)
      { success: status.success?, output: output.strip }
    end
  rescue Errno::ENOENT
    { success: false, output: "Command not found: #{cmd.split.first}" }
  rescue Timeout::Error
    { success: false, output: "Timed out after 15s" }
  rescue StandardError => e
    { success: false, output: e.message }
  end

  def clear_keys(prefix)
    Setting.where(key: [prefix, "#{prefix}_checked_at"]).destroy_all
  end
end
