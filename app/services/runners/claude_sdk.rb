module Runners
  # Placeholder for a future runner backed by the Claude Agent SDK. Establishes
  # the seam so StepExecutor can dispatch through a runner abstraction today
  # while a real SDK-backed implementation is added later (Python sidecar via
  # Open3, or a TypeScript sidecar). When introduced, this runner should give
  # us native structured outputs, programmatic subagents, and PreToolUse /
  # PostToolUse hooks.
  class ClaudeSDK < Base
    def execute(**)
      raise NotImplementedError,
            "Runners::ClaudeSDK is a seam placeholder. Set Setting['default_runner'] = 'claude_cli' " \
            "or configure the SDK runner before using it."
    end
  end
end
