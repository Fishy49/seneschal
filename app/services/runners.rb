module Runners
  class UnknownRunnerError < StandardError; end

  # Raised by a streaming runner's progress block when the caller wants to
  # abort mid-conversation (e.g. ExecuteRunJob detecting it's been
  # superseded by RunRecoveryJob handing the run off to a new worker).
  # Distinct class so runner-level `rescue StandardError` can recognize it
  # and re-raise instead of swallowing into a failed Result.
  class Aborted < StandardError; end

  DEFAULT_NAME = "claude_cli".freeze
  # Whitelist for operator-facing pickers (workflow form, Setting). Keep in
  # sync with `lookup`'s case below.
  KNOWN_NAMES = ["claude_cli", "claude_sdk"].freeze

  def self.lookup(name)
    case name.to_s
    when "claude_cli" then ClaudeCLI.new
    when "claude_sdk" then ClaudeSDK.new
    else
      raise UnknownRunnerError, "Unknown runner: #{name.inspect}"
    end
  end

  def self.default_name
    Setting["default_runner"].presence || DEFAULT_NAME
  end
end
