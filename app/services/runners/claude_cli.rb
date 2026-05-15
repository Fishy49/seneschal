require "open3"

module Runners
  class ClaudeCLI < Base
    BROADCAST_INTERVAL = 2.0 # seconds between progress yields

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
      # ignored by CLI; only ClaudeSDK supports schema-validated outputs
      json_schema: nil, # rubocop:disable Lint/UnusedMethodArgument
      &
    )
      cmd = build_cmd(
        prompt: prompt,
        resume_session_id: resume_session_id,
        resume_message: resume_message,
        model: model,
        max_turns: max_turns,
        effort: effort,
        allowed_tools: allowed_tools,
        dangerously_skip_permissions: dangerously_skip_permissions,
        permission_mode: permission_mode,
        add_dirs: add_dirs,
        stream: stream
      )

      if stream && block_given?
        execute_streaming(cmd, env: env, cwd: cwd, &)
      else
        run_command(cmd, env: env, cwd: cwd)
      end
    end

    # Public so tests can introspect the constructed CLI invocation directly.
    # Accepts and ignores extra kwargs (cwd:, env:) so callers can splat the
    # full runner-call hash without slicing.
    def build_cmd( # rubocop:disable Metrics/ParameterLists
      prompt:,
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
      **_
    )
      cmd = ["claude"]

      if resume_session_id
        cmd += ["--resume", resume_session_id, "-p"]
        cmd += ["--output-format", "stream-json"] if stream
        cmd += ["--verbose"]
        cmd << (resume_message || "Your previous session was interrupted. Continue and complete the task.")
      else
        cmd += ["-p"]
        cmd += ["--output-format", "stream-json"] if stream
        cmd += ["--verbose"]
        cmd << prompt
      end

      cmd += ["--model", model] if model.present?
      cmd += ["--max-turns", max_turns.to_s] if max_turns.present?
      cmd += ["--effort", effort.presence || "medium"]

      if dangerously_skip_permissions
        cmd += ["--dangerously-skip-permissions"]
      else
        cmd += ["--permission-mode", permission_mode]
        cmd += ["--allowedTools", allowed_tools] if allowed_tools.present?
      end

      add_dirs.each { |path| cmd += ["--add-dir", path] }

      cmd
    end

    private

    def execute_streaming(cmd, env:, cwd:)
      events = []
      result_text = +""
      stderr_acc = +""
      session_id = nil

      Open3.popen3(env, *cmd, chdir: cwd) do |stdin, stdout, stderr, wait_thr|
        stdin.close
        stderr_thread = Thread.new { stderr_acc = stderr.read }

        last_broadcast = monotonic_now

        stdout.each_line do |line|
          line = line.strip
          next if line.empty?

          event = begin; JSON.parse(line); rescue StandardError; next; end
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
          stream_events: events, session_id: session_id
        )
      end
    rescue StandardError => e
      Result.new(exit_code: 1, stdout: "", stderr: e.message)
    end

    def run_command(cmd, env:, cwd:)
      stdout, stderr, status = Open3.capture3(env, *cmd, chdir: cwd)
      Result.new(exit_code: status.exitstatus || 1, stdout: stdout, stderr: stderr)
    rescue StandardError => e
      Result.new(exit_code: 1, stdout: "", stderr: e.message)
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
