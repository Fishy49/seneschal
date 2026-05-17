require "open3"
require "json"

module Runners
  # Routes Skill / Prompt steps through the Claude Agent SDK rather than the
  # `claude` CLI binary. Because Seneschal is Ruby and the SDK is Python-only,
  # this runner spawns a one-shot Python sidecar (lib/sdk_runner) per step,
  # passes a JSON config on stdin, and parses NDJSON events from stdout in the
  # same shape as the CLI's `--output-format stream-json`. Net effect: a drop-in
  # replacement for ClaudeCLI with access to structured outputs, hooks, and
  # subagents on the Python side.
  #
  # Opt in per-step via `Step.config["runner"] = "claude_sdk"` or globally via
  # `Setting["default_runner"] = "claude_sdk"`.
  class ClaudeSDK < Base
    class SdkRunnerMissing < StandardError; end

    BROADCAST_INTERVAL = 2.0 # seconds between progress yields
    DEFAULT_PYTHON_BIN = "python3".freeze
    BUNDLED_VENV_PYTHON = Rails.root.join("lib/sdk_runner/.venv/bin/python").to_s.freeze
    DEFAULT_RUNNER_SCRIPT = Rails.root.join("lib/sdk_runner/src/seneschal_sdk_runner/main.py").to_s.freeze

    def supports_structured_outputs?
      true
    end

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
      &
    )
      config = build_config(
        prompt: prompt, cwd: cwd,
        resume_session_id: resume_session_id, resume_message: resume_message,
        model: model, max_turns: max_turns, effort: effort,
        allowed_tools: allowed_tools, dangerously_skip_permissions: dangerously_skip_permissions,
        permission_mode: permission_mode, add_dirs: add_dirs,
        json_schema: json_schema, hooks: hooks, agents: agents, mcp_servers: mcp_servers
      )

      ensure_runner_script!

      if stream && block_given?
        execute_streaming(config, env: env, cwd: cwd, &)
      else
        execute_buffered(config, env: env, cwd: cwd)
      end
    end

    # Build the wire-protocol JSON payload sent to the Python sidecar.
    # Public so tests can introspect what gets sent without spawning Python.
    def build_config( # rubocop:disable Metrics/ParameterLists
      prompt:,
      cwd:,
      resume_session_id: nil,
      resume_message: nil,
      model: nil,
      max_turns: nil,
      effort: "medium", # ignored by the SDK runner; preserved for runner-interface parity
      allowed_tools: nil,
      dangerously_skip_permissions: false,
      permission_mode: "dontAsk",
      add_dirs: [],
      json_schema: nil,
      hooks: nil,
      agents: nil,
      mcp_servers: nil,
      **_
    )
      {
        "prompt" => prompt,
        "cwd" => cwd,
        "resume_session_id" => resume_session_id,
        "resume_message" => resume_message,
        "model" => model.presence,
        "max_turns" => max_turns,
        "effort" => effort,
        "allowed_tools" => normalize_allowed_tools(allowed_tools),
        "dangerously_skip_permissions" => dangerously_skip_permissions ? true : false,
        "permission_mode" => permission_mode,
        "add_dirs" => Array(add_dirs),
        "json_schema" => json_schema,
        "hooks" => hooks,
        "agents" => agents,
        "mcp_servers" => mcp_servers
      }
    end

    # The Python interpreter to spawn. Resolution order:
    #   1. Setting["python_bin"] — operator-provided override (full path)
    #   2. lib/sdk_runner/.venv/bin/python — bundled venv created by bin/setup_sdk_runner
    #   3. system "python3" — last-resort fallback (assumes claude-agent-sdk is on PATH)
    def python_bin
      override = Setting["python_bin"].presence
      return override if override
      return BUNDLED_VENV_PYTHON if File.executable?(BUNDLED_VENV_PYTHON)

      DEFAULT_PYTHON_BIN
    end

    # The runner script path. Overridable via Setting["sdk_runner_script"] —
    # primarily a test seam so the runner can spawn a stub interpreter +
    # fake script, but also a useful escape hatch for operators with an
    # unusual install layout.
    def runner_script
      Setting["sdk_runner_script"].presence || DEFAULT_RUNNER_SCRIPT
    end

    private

    def normalize_allowed_tools(allowed_tools)
      case allowed_tools
      when nil then nil
      when Array then allowed_tools
      when String then allowed_tools.split(",").map(&:strip).reject(&:empty?)
      else Array(allowed_tools)
      end
    end

    def ensure_runner_script!
      return if File.exist?(runner_script)

      raise SdkRunnerMissing,
            "SDK runner script missing at #{runner_script}. " \
            "Run bin/setup_sdk_runner."
    end

    def execute_streaming(config, env:, cwd:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      events = []
      result_text = +""
      stderr_acc = +""
      session_id = nil

      Open3.popen3(env, python_bin, runner_script, chdir: cwd) do |stdin, stdout, stderr, wait_thr|
        stdin.write(JSON.dump(config))
        stdin.close
        stderr_thread = Thread.new { stderr_acc = stderr.read }

        last_broadcast = monotonic_now

        stdout.each_line do |line|
          line = line.strip
          next if line.empty?

          event = begin
            JSON.parse(line)
          rescue StandardError
            next
          end
          events << event
          session_id ||= event["session_id"]

          case event["type"]
          when "result"
            result_text = event["result"].to_s
            session_id ||= event["session_id"]
          when "assistant"
            (event.dig("message", "content") || []).each do |block|
              result_text = block["text"] if block["type"] == "text"
            end
          when "error"
            stderr_acc = [stderr_acc, event["message"]].compact.reject(&:empty?).join("\n")
          end

          if monotonic_now - last_broadcast >= BROADCAST_INTERVAL
            yield({ stream_log: events.dup, output: result_text.dup, claude_session_id: session_id })
            last_broadcast = monotonic_now
          end
        end

        stderr_thread.join
        exit_code = wait_thr.value.exitstatus || 1

        yield({ stream_log: events.dup, output: result_text.dup, claude_session_id: session_id })

        Result.new(
          exit_code: exit_code, stdout: result_text, stderr: stderr_acc,
          stream_events: events, session_id: session_id,
          structured_output: structured_output_from(events)
        )
      end
    rescue StandardError => e
      Result.new(exit_code: 1, stdout: "", stderr: e.message)
    end

    def execute_buffered(config, env:, cwd:)
      stdout, stderr, status = Open3.capture3(
        env, python_bin, runner_script,
        stdin_data: JSON.dump(config),
        chdir: cwd
      )

      events = stdout.each_line.filter_map do |line|
        JSON.parse(line.strip)
      rescue StandardError
        nil
      end

      result_event = events.reverse.find { |e| e["type"] == "result" }
      session_id = events.filter_map { |e| e["session_id"] }.first

      # The sidecar emits `error` events on stdout (so they thread through the
      # same NDJSON stream as everything else). Pull them out and merge with
      # the OS-level stderr so the Result's stderr is the union of both.
      error_msgs = events.select { |e| e["type"] == "error" }.map { |e| e["message"].to_s }
      merged_stderr = [stderr, *error_msgs].reject { |s| s.to_s.empty? }.join("\n")

      Result.new(
        exit_code: status.exitstatus || 1,
        stdout: result_event&.dig("result").to_s,
        stderr: merged_stderr,
        stream_events: events,
        session_id: session_id,
        structured_output: structured_output_from(events)
      )
    rescue StandardError => e
      Result.new(exit_code: 1, stdout: "", stderr: e.message)
    end

    # Pulls a non-nil `structured_output` field off the most recent `result`
    # event. Only populated when the wire config carried a `json_schema`
    # and the SDK actually emitted a schema-conforming object.
    def structured_output_from(events)
      result_event = events.reverse.find { |e| e["type"] == "result" }
      result_event && result_event["structured_output"]
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
