module Runners
  class UnknownRunnerError < StandardError; end

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
