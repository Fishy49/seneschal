require "open3"

class StepExecutor
  include ContextFetcher

  Result = Data.define(:exit_code, :stdout, :stderr, :stream_events) do
    def initialize(exit_code:, stdout:, stderr:, stream_events: nil)
      super
    end

    def passed? = exit_code.zero?
  end

  BROADCAST_INTERVAL = 2.0 # seconds between progress broadcasts
  DEFAULT_ALLOWED_TOOLS = "Bash,Read,Edit,Glob,Grep".freeze

  def initialize(step, context, repo_path, resolved_input_context: nil, resume_session_id: nil)
    @step = step
    @context = context
    @repo_path = repo_path
    @resolved_input_context = resolved_input_context
    @resume_session_id = resume_session_id
  end

  def execute(&)
    case @step.step_type
    when "skill", "prompt" then execute_skill(&)
    when "script"   then execute_script(&)
    when "command"  then execute_command(&)
    when "ci_check" then execute_ci_check
    when "context_fetch" then execute_context_fetch(&)
    else
      Result.new(exit_code: 1, stdout: "", stderr: "Unknown step type: #{@step.step_type}")
    end
  end

  private

  def execute_skill(&)
    prompt = @step.prompt_body(@context)
    return Result.new(exit_code: 1, stdout: "", stderr: "No prompt content") unless prompt

    prompt = "#{prompt}\n\n## Additional Context\n\n#{@resolved_input_context}" if @resolved_input_context.present?

    cmd = build_skill_cmd(prompt, stream: block_given?)

    if block_given?
      execute_skill_streaming(cmd, &)
    else
      run_command(cmd)
    end
  end

  def execute_script(&)
    body = interpolate_string(@step.body)
    if block_given?
      run_command_streaming(["bash", "-c", body], chdir: @repo_path, &)
    else
      run_command(["bash", "-c", body], chdir: @repo_path)
    end
  end

  def execute_command(&)
    body = interpolate_string(@step.body)
    if block_given?
      run_command_streaming(["bash", "-c", body], chdir: @repo_path, &)
    else
      run_command(["bash", "-c", body], chdir: @repo_path)
    end
  end

  def execute_ci_check(&)
    cfg = @step.config
    mode = cfg.fetch("mode", "pr")

    case mode
    when "pr" then poll_pr_checks(cfg, &)
    when "workflow" then poll_workflow_run(cfg, &)
    else
      Result.new(exit_code: 1, stdout: "", stderr: "Unknown ci_check mode: #{mode}")
    end
  rescue StandardError => e
    Result.new(exit_code: 1, stdout: "", stderr: e.message)
  end

  # --- Streaming execution ---

  def execute_skill_streaming(cmd)
    events = []
    result_text = +""
    stderr_acc = +""
    session_id = nil

    Open3.popen3(env_vars, *cmd, chdir: @repo_path) do |stdin, stdout, stderr, wait_thr|
      stdin.close
      stderr_thread = Thread.new { stderr_acc = stderr.read }

      last_broadcast = monotonic_now

      stdout.each_line do |line|
        line = line.strip
        next if line.empty?

        event = begin; JSON.parse(line); rescue StandardError; next; end
        events << event

        # Capture session_id from the earliest event that has one
        session_id ||= event["session_id"]

        # Extract text from result or assistant text blocks
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

      # Final broadcast
      yield({ stream_log: events.dup, output: result_text.dup, claude_session_id: session_id })

      Result.new(exit_code: exit_code, stdout: result_text, stderr: stderr_acc, stream_events: events)
    end
  rescue StandardError => e
    Result.new(exit_code: 1, stdout: "", stderr: e.message)
  end

  def run_command_streaming(cmd, chdir: nil)
    stdout_acc = +""
    stderr_acc = +""

    Open3.popen3(env_vars, *cmd, chdir: chdir || @repo_path) do |stdin, stdout, stderr, wait_thr|
      stdin.close
      stderr_thread = Thread.new { stderr_acc = stderr.read }

      last_broadcast = monotonic_now

      stdout.each_line do |line|
        stdout_acc << line

        if monotonic_now - last_broadcast >= BROADCAST_INTERVAL
          yield({ output: stdout_acc.dup, error_output: stderr_acc.dup })
          last_broadcast = monotonic_now
        end
      end

      stderr_thread.join
      exit_code = wait_thr.value.exitstatus || 1

      yield({ output: stdout_acc.dup, error_output: stderr_acc.dup })

      Result.new(exit_code: exit_code, stdout: stdout_acc, stderr: stderr_acc)
    end
  rescue StandardError => e
    Result.new(exit_code: 1, stdout: "", stderr: e.message)
  end

  # --- Skill command builder ---

  def build_skill_cmd(prompt, stream: false)
    cmd = ["claude"]

    if @resume_session_id
      cmd += ["--resume", @resume_session_id, "-p"]
      cmd += ["--output-format", "stream-json"] if stream
      cmd += ["--verbose"]
      cmd << "Your previous session was interrupted. Continue and complete the task."
    else
      cmd += ["-p"]
      cmd += ["--output-format", "stream-json"] if stream
      cmd += ["--verbose"]
      cmd << prompt
    end

    model = @step.config["model"]
    cmd += ["--model", model] if model.present?

    max_turns = @step.config["max_turns"]
    cmd += ["--max-turns", max_turns.to_s] if max_turns.present?

    effort = @step.config["effort"].presence || "medium"
    cmd += ["--effort", effort]

    cmd += ["--permission-mode", "dontAsk"]

    allowed = @step.config["allowed_tools"].presence ||
              Setting["default_allowed_tools"].presence ||
              DEFAULT_ALLOWED_TOOLS
    cmd += ["--allowedTools", allowed]

    cmd
  end

  # --- Non-streaming execution ---

  def run_command(cmd, chdir: nil)
    stdout, stderr, status = Open3.capture3(
      env_vars,
      *cmd,
      chdir: chdir || @repo_path
    )

    Result.new(exit_code: status.exitstatus || 1, stdout: stdout, stderr: stderr)
  rescue StandardError => e
    Result.new(exit_code: 1, stdout: "", stderr: e.message)
  end

  # --- CI polling (unchanged) ---

  def poll_pr_checks(cfg)
    pr = interpolate_string(cfg.fetch("pr", "${pr_number}"))
    poll_interval = cfg.fetch("poll_interval", 30)
    deadline = Time.current + @step.timeout

    sleep 5

    loop do
      yield({ output: "Polling CI checks for PR ##{pr}..." }) if block_given?
      stdout, _, status = Open3.capture3(
        env_vars,
        "gh", "pr", "checks", pr.to_s, "--json", "name,bucket,link",
        chdir: @repo_path
      )

      if status.success?
        checks = begin; JSON.parse(stdout); rescue StandardError; []; end

        if checks.any?
          pending = checks.select { |c| c["bucket"] == "pending" }

          if pending.empty?
            failed = checks.select { |c| c["bucket"] == "fail" }
            summary = checks.map do |c|
              "#{c["bucket"] == "fail" ? "FAIL" : "PASS"} #{c["name"]}"
            end.join("\n")

            return Result.new(exit_code: 0, stdout: "All CI checks passed:\n#{summary}", stderr: "") if failed.empty?

            max_chars = cfg.fetch("max_log_chars", 10_000)
            log_from = cfg.fetch("log_from", "end")
            failure_logs = fetch_failure_logs(failed, max_chars: max_chars, from: log_from)
            output = "CI checks failed:\n#{summary}\n\n#{failure_logs}".strip
            return Result.new(exit_code: 1, stdout: output, stderr: "")

          end
        end
      end

      return Result.new(exit_code: 1, stdout: stdout.to_s, stderr: "CI checks timed out after #{@step.timeout}s") if Time.current > deadline

      sleep poll_interval
    end
  end

  def fetch_failure_logs(failed_checks, max_chars: 10_000, from: "end")
    # Extract unique run IDs from check links
    # Link format: https://github.com/OWNER/REPO/actions/runs/RUN_ID/job/JOB_ID
    run_ids = failed_checks.filter_map { |c| c["link"]&.match(%r{/runs/(\d+)})&.[](1) }.uniq
    per_run_limit = run_ids.size > 1 ? max_chars / run_ids.size : max_chars

    logs = run_ids.filter_map do |run_id|
      stdout, _, status = Open3.capture3(
        env_vars,
        "gh", "run", "view", run_id, "--log-failed",
        chdir: @repo_path
      )
      next unless status.success? && stdout.present?

      # Clean up GitHub Actions log formatting
      clean = stdout.lines.map do |l|
        l.gsub(/\e\[[0-9;]*m/, "")                        # strip ANSI codes
         .sub(/\d{4}-\d{2}-\d{2}T[\d:.]+Z\s*/, "")        # strip timestamps
         .sub(/^[^\t]+\t[^\t]+\t/, "") # strip "job\tstep\t" prefix
         .sub(/^\W*##\[(group|endgroup|error)\].*\n?/, "") # strip GH workflow marker lines (incl BOM)
      end.reject { |l| l.strip.blank? }.join

      if clean.length > per_run_limit
        trimmed = clean.length - per_run_limit
        clean = if from == "beginning"
                  "#{clean.first(per_run_limit)}\n\n... (truncated #{trimmed} chars from end) ..."
                else
                  "... (truncated #{trimmed} chars from start) ...\n\n#{clean.last(per_run_limit)}"
                end
      end
      clean
    end

    logs.join("\n\n---\n\n")
  rescue StandardError => e
    "(Could not fetch failure logs: #{e.message})"
  end

  def poll_workflow_run(cfg)
    workflow_file = interpolate_string(cfg.fetch("workflow", "ci.yml"))
    ref = interpolate_string(cfg.fetch("ref", "main"))
    should_trigger = cfg.fetch("trigger", false)
    poll_interval = cfg.fetch("poll_interval", 30)
    deadline = Time.current + @step.timeout

    if should_trigger
      _, stderr, status = Open3.capture3(
        env_vars,
        "gh", "workflow", "run", workflow_file, "--ref", ref,
        chdir: @repo_path
      )
      return Result.new(exit_code: 1, stdout: "", stderr: "Failed to trigger workflow: #{stderr}") unless status.success?

      sleep 5
    end

    loop do
      yield({ output: "Polling workflow '#{workflow_file}'..." }) if block_given?

      stdout, _, status = Open3.capture3(
        env_vars,
        "gh", "run", "list",
        "--workflow", workflow_file,
        "--branch", ref,
        "--limit", "1",
        "--json", "databaseId,status,conclusion",
        chdir: @repo_path
      )

      if status.success?
        runs = begin; JSON.parse(stdout); rescue StandardError; []; end

        if runs.any?
          run_data = runs.first
          if run_data["status"] == "completed"
            if run_data["conclusion"] == "success"
              return Result.new(exit_code: 0, stdout: "Workflow '#{workflow_file}' passed (run ##{run_data["databaseId"]})", stderr: "")
            end

            return Result.new(exit_code: 1,
                              stdout: "Workflow '#{workflow_file}' #{run_data["conclusion"]} (run ##{run_data["databaseId"]})", stderr: "")

          end
        end
      end

      return Result.new(exit_code: 1, stdout: "", stderr: "Workflow timed out after #{@step.timeout}s") if Time.current > deadline

      sleep poll_interval
    end
  end

  # --- Helpers ---

  def env_vars
    vars = @context.transform_keys { |k| k.to_s.upcase }.merge(
      "REPO_PATH" => @repo_path
    )
    vars["INPUT_CONTEXT"] = @resolved_input_context if @resolved_input_context.present?
    vars
  end

  def interpolate_string(str)
    str.to_s.gsub(/\$\{(\w+)\}/) do
      @context[::Regexp.last_match(1)] || @context[::Regexp.last_match(1).to_sym] || "${#{::Regexp.last_match(1)}}"
    end
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
