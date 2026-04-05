require "open3"

class StepExecutor
  Result = Data.define(:exit_code, :stdout, :stderr, :stream_events) do
    def initialize(exit_code:, stdout:, stderr:, stream_events: nil)
      super
    end

    def passed? = exit_code == 0
  end

  BROADCAST_INTERVAL = 2.0 # seconds between progress broadcasts

  def initialize(step, context, repo_path, resolved_input_context: nil)
    @step = step
    @context = context
    @repo_path = repo_path
    @resolved_input_context = resolved_input_context
  end

  def execute(&on_progress)
    case @step.step_type
    when "skill"    then execute_skill(&on_progress)
    when "script"   then execute_script(&on_progress)
    when "command"  then execute_command(&on_progress)
    when "ci_check" then execute_ci_check
    else
      Result.new(exit_code: 1, stdout: "", stderr: "Unknown step type: #{@step.step_type}")
    end
  end

  private

  def execute_skill(&on_progress)
    prompt = @step.prompt_body(@context)
    return Result.new(exit_code: 1, stdout: "", stderr: "No skill assigned") unless prompt

    if @resolved_input_context.present?
      prompt = "#{prompt}\n\n## Additional Context\n\n#{@resolved_input_context}"
    end

    cmd = build_skill_cmd(prompt, stream: block_given?)

    if block_given?
      execute_skill_streaming(cmd, &on_progress)
    else
      run_command(cmd)
    end
  end

  def execute_script(&on_progress)
    body = interpolate_string(@step.body)
    if block_given?
      run_command_streaming(["bash", "-c", body], chdir: @repo_path, &on_progress)
    else
      run_command(["bash", "-c", body], chdir: @repo_path)
    end
  end

  def execute_command(&on_progress)
    body = interpolate_string(@step.body)
    if block_given?
      run_command_streaming(["bash", "-c", body], chdir: @repo_path, &on_progress)
    else
      run_command(["bash", "-c", body], chdir: @repo_path)
    end
  end

  def execute_ci_check
    cfg = @step.config
    mode = cfg.fetch("mode", "pr")

    case mode
    when "pr"       then poll_pr_checks(cfg)
    when "workflow"  then poll_workflow_run(cfg)
    else
      Result.new(exit_code: 1, stdout: "", stderr: "Unknown ci_check mode: #{mode}")
    end
  rescue => e
    Result.new(exit_code: 1, stdout: "", stderr: e.message)
  end

  # --- Streaming execution ---

  def execute_skill_streaming(cmd, &on_progress)
    events = []
    result_text = +""
    stderr_acc = +""

    Open3.popen3(env_vars, *cmd, chdir: @repo_path) do |stdin, stdout, stderr, wait_thr|
      stdin.close
      stderr_thread = Thread.new { stderr_acc = stderr.read }

      last_broadcast = monotonic_now

      stdout.each_line do |line|
        line = line.strip
        next if line.empty?

        event = begin; JSON.parse(line); rescue; next; end
        events << event

        # Extract text from result or assistant text blocks
        case event["type"]
        when "result"
          result_text = event["result"].to_s
        when "assistant"
          (event.dig("message", "content") || []).each do |block|
            result_text = block["text"] if block["type"] == "text"
          end
        end

        if monotonic_now - last_broadcast >= BROADCAST_INTERVAL
          yield({ stream_log: events.dup, output: result_text.dup })
          last_broadcast = monotonic_now
        end
      end

      stderr_thread.join
      exit_code = wait_thr.value.exitstatus || 1

      # Final broadcast
      yield({ stream_log: events.dup, output: result_text.dup })

      Result.new(exit_code: exit_code, stdout: result_text, stderr: stderr_acc, stream_events: events)
    end
  rescue => e
    Result.new(exit_code: 1, stdout: "", stderr: e.message)
  end

  def run_command_streaming(cmd, chdir: nil, &on_progress)
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
  rescue => e
    Result.new(exit_code: 1, stdout: "", stderr: e.message)
  end

  # --- Skill command builder ---

  def build_skill_cmd(prompt, stream: false)
    cmd = ["claude", "-p"]
    cmd += ["--output-format", "stream-json"] if stream
    cmd += ["--verbose"]
    cmd << prompt

    model = @step.config["model"]
    cmd += ["--model", model] if model.present?

    max_turns = @step.config["max_turns"]
    cmd += ["--max-turns", max_turns.to_s] if max_turns.present?

    allowed = @step.config["allowed_tools"]
    if allowed.present?
      cmd += ["--allowedTools", allowed]
    else
      cmd += ["--dangerously-skip-permissions"]
    end

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
  rescue => e
    Result.new(exit_code: 1, stdout: "", stderr: e.message)
  end

  # --- CI polling (unchanged) ---

  def poll_pr_checks(cfg)
    pr = interpolate_string(cfg.fetch("pr", "${pr_number}"))
    poll_interval = cfg.fetch("poll_interval", 30)
    deadline = Time.current + @step.timeout

    sleep 5

    loop do
      stdout, stderr, status = Open3.capture3(
        env_vars,
        "gh", "pr", "checks", pr.to_s, "--json", "name,bucket,link",
        chdir: @repo_path
      )

      if status.success?
        checks = begin; JSON.parse(stdout); rescue; []; end

        if checks.any?
          pending = checks.select { |c| c["bucket"] == "pending" }

          if pending.empty?
            failed = checks.select { |c| c["bucket"] == "fail" }
            summary = checks.map { |c|
              "#{c['bucket'] == 'fail' ? 'FAIL' : 'PASS'} #{c['name']}"
            }.join("\n")

            if failed.empty?
              return Result.new(exit_code: 0, stdout: "All CI checks passed:\n#{summary}", stderr: "")
            else
              failure_logs = fetch_failure_logs(failed)
              output = "CI checks failed:\n#{summary}\n\n#{failure_logs}".strip
              return Result.new(exit_code: 1, stdout: output, stderr: "")
            end
          end
        end
      end

      if Time.current > deadline
        return Result.new(exit_code: 1, stdout: stdout.to_s, stderr: "CI checks timed out after #{@step.timeout}s")
      end

      sleep poll_interval
    end
  end

  def fetch_failure_logs(failed_checks)
    # Extract unique run IDs from check links
    # Link format: https://github.com/OWNER/REPO/actions/runs/RUN_ID/job/JOB_ID
    run_ids = failed_checks.filter_map { |c| c["link"]&.match(%r{/runs/(\d+)})&.[](1) }.uniq

    logs = run_ids.filter_map do |run_id|
      stdout, _, status = Open3.capture3(
        env_vars,
        "gh", "run", "view", run_id, "--log-failed",
        chdir: @repo_path
      )
      next unless status.success? && stdout.present?

      # Clean up GitHub Actions log formatting
      clean = stdout.lines.map { |l|
        l.gsub(/\e\[[0-9;]*m/, "")                        # strip ANSI codes
         .sub(/\d{4}-\d{2}-\d{2}T[\d:.]+Z\s*/, "")        # strip timestamps
         .sub(/^[^\t]+\t[^\t]+\t/, "")                     # strip "job\tstep\t" prefix
         .sub(/^\W*##\[(group|endgroup|error)\].*\n?/, "")     # strip GH workflow marker lines (incl BOM)
      }.reject { |l| l.strip.blank? }.join

      clean.truncate(10_000)
    end

    logs.join("\n\n---\n\n")
  rescue => e
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
      unless status.success?
        return Result.new(exit_code: 1, stdout: "", stderr: "Failed to trigger workflow: #{stderr}")
      end
      sleep 5
    end

    loop do
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
        runs = begin; JSON.parse(stdout); rescue; []; end

        if runs.any?
          run_data = runs.first
          if run_data["status"] == "completed"
            if run_data["conclusion"] == "success"
              return Result.new(exit_code: 0, stdout: "Workflow '#{workflow_file}' passed (run ##{run_data['databaseId']})", stderr: "")
            else
              return Result.new(exit_code: 1, stdout: "Workflow '#{workflow_file}' #{run_data['conclusion']} (run ##{run_data['databaseId']})", stderr: "")
            end
          end
        end
      end

      if Time.current > deadline
        return Result.new(exit_code: 1, stdout: "", stderr: "Workflow timed out after #{@step.timeout}s")
      end

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
      @context[$1] || @context[$1.to_sym] || "${#{$1}}"
    end
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
