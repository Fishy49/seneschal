module Runners
  # Abstract base for agent runners. Subclasses must implement #execute, which
  # invokes an underlying agent (Claude CLI, Claude Agent SDK, etc.) and
  # returns a Runners::Result.
  #
  # Streaming: when `stream:` is true and a block is given, the runner yields
  # progress updates to the block. Each yield is a Hash with the keys:
  #   - stream_log: Array of NDJSON-style event hashes (runner-specific shape)
  #   - output: current accumulated text output
  #   - claude_session_id: session id captured from the underlying agent, if any
  #
  # All knobs (model, allowed_tools, add_dirs, etc.) are passed as kwargs;
  # runners are free to ignore knobs they don't support.
  class Base
    def execute( # rubocop:disable Metrics/ParameterLists
      prompt:,
      cwd:,
      env: {},
      resume_session_id: nil,
      resume_message: nil,
      model: nil,
      max_turns: nil,
      effort: "medium",
      allowed_tools: nil,
      dangerously_skip_permissions: false,
      permission_mode: "dontAsk",
      add_dirs: [],
      stream: false,
      json_schema: nil,
      hooks: nil,
      agents: nil,
      mcp_servers: nil,
      &block
    )
      raise NotImplementedError, "#{self.class} must implement #execute"
    end

    # Whether this runner can enforce a JSON schema natively (via constrained
    # generation / tool injection) and surface the parsed object back on
    # Result#structured_output. When true, StepExecutor will NOT append
    # inline-JSON-emit instructions to the prompt — the runner handles it.
    # When false, the prompt-engineered ```output block``` fallback is used.
    def supports_structured_outputs?
      false
    end
  end
end
