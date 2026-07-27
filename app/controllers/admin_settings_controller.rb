class AdminSettingsController < ApplicationController
  before_action :require_admin

  # Free-text keys, written through verbatim after stripping. Everything that
  # needs shaping or validating is handled explicitly in `update`.
  TEXT_KEYS = [
    "default_allowed_tools", "skills_global_roots", "skill_repo_root", "worktree_root",
    "run_assets_root", "python_bin", "sdk_runner_script",
    "webhook_url", "slack_webhook_url", "app_base_url"
  ].freeze

  def show
    load_settings
  end

  def update
    if (error = validation_error)
      load_settings
      flash.now[:alert] = error
      render :show, status: :unprocessable_content
      return
    end

    TEXT_KEYS.each { |key| write(key, params[key]) }
    write("default_runner", params[:default_runner]) if Runners::KNOWN_NAMES.include?(params[:default_runner].to_s)
    write("worktree_retention_days", params[:worktree_retention_days])
    write("mcp_servers", params[:mcp_servers])
    # Always explicit: the consumer reads a missing key as "confine", and an
    # empty string would cast to false and quietly widen write access.
    Setting["confine_writes_to_cwd"] = ActiveModel::Type::Boolean.new.cast(params[:confine_writes_to_cwd]) ? "true" : "false"

    redirect_to admin_settings_path, notice: "Server settings saved."
  end

  private

  def load_settings
    @claude = IntegrationStatus.for("claude_cli")
    @gh = IntegrationStatus.for("gh_cli")
    @sdk_runner = IntegrationStatus.for("sdk_runner")
    @legacy_global_root = Setting["skills_global_root"].presence
  end

  # A blank value removes the row entirely, so consumers see nil and fall back
  # to their own default rather than to an empty string.
  def write(key, value)
    stripped = value.to_s.strip
    if stripped.empty?
      Setting.find_by(key: key)&.destroy
    else
      Setting[key] = stripped
    end
  end

  def validation_error
    days = params[:worktree_retention_days].to_s.strip
    return "Worktree retention must be a whole number of days, 1 or more." if days.present? && !days.match?(/\A[1-9]\d*\z/)

    mcp = params[:mcp_servers].to_s.strip
    return nil if mcp.empty?

    parsed = begin
      JSON.parse(mcp)
    rescue JSON::ParserError
      nil
    end
    "MCP servers must be a JSON object mapping a server name to its config." unless parsed.is_a?(Hash)
  end
end
