require "open3"

class StepExecutor # rubocop:disable Metrics/ClassLength
  include ContextFetcher
  include PrCreator

  # Backwards-compatible alias. Result lives in Runners::Result now so all
  # runners share one struct; consumers (ExecuteRunJob, tests) can continue
  # to reference StepExecutor::Result.
  Result = Runners::Result

  BROADCAST_INTERVAL = 2.0 # seconds between progress broadcasts
  DEFAULT_ALLOWED_TOOLS = "Bash,Read,Edit,Glob,Grep".freeze

  # Tools available to a self_review step. Read-only by design — a step that
  # could Write or Edit defeats its own purpose as a review checkpoint.
  SELF_REVIEW_TOOLS = "Read,Grep,Glob".freeze
  REVIEW_DIFF_MAX_CHARS = 80_000

  # Icon prefixes for the live ci_check status panel. Bucket names match
  # `gh pr checks --json bucket`.
  CHECK_BUCKET_ICONS = {
    "pending" => "⏳",
    "pass" => "✅",
    "fail" => "❌",
    "skipping" => "⏭"
  }.freeze

  # Subset of git's ref-name rules — strict enough to keep an attacker-
  # controlled `base_ref` value from sneaking through as a `git diff` flag
  # (no leading dashes, no shell metacharacters, no ".." segments). We
  # intentionally accept less than git's full ruleset.
  SAFE_GIT_REF = %r{\A[A-Za-z0-9_][A-Za-z0-9._/-]*\z}

  def initialize(step, context, repo_path, # rubocop:disable Metrics/ParameterLists
                 resolved_input_context: nil, resume_session_id: nil,
                 resume_message: nil, run_step_id: nil, runner: nil)
    @step = step
    @context = context
    @repo_path = repo_path
    @resolved_input_context = resolved_input_context
    @resume_session_id = resume_session_id
    @resume_message = resume_message
    @run_step_id = run_step_id
    @runner = runner
  end

  # The agent runner this executor dispatches skill/prompt steps through.
  # Resolved from Step.config["runner"] (per-step override) or Setting["default_runner"].
  def runner
    @runner ||= Runners.lookup(runner_name)
  end

  # Runner resolution precedence:
  #   1. Step.config["runner"]   — finest-grained override
  #   2. Workflow#runner_name    — workflow-level pick (e.g. "this workflow
  #                                 uses structured outputs, route everything
  #                                 through the SDK")
  #   3. Setting["default_runner"] / Runners.default_name — global fallback
  def runner_name
    @step.config["runner"].presence ||
      workflow_for_step&.runner_name ||
      Runners.default_name
  end

  def workflow_for_step
    @workflow_for_step ||= @step.workflow || @step.run&.workflow
  end

  def execute(&)
    case @step.step_type
    when "skill", "prompt" then execute_skill(&)
    when "script"   then execute_script(&)
    when "command"  then execute_command(&)
    when "ci_check" then execute_ci_check
    when "context_fetch" then execute_context_fetch(&)
    when "pr" then execute_pr_step(&)
    when "self_review" then execute_self_review(&)
    else
      Result.new(exit_code: 1, stdout: "", stderr: "Unknown step type: #{@step.step_type}")
    end
  end

  private

  def execute_skill(&) # rubocop:disable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
    prompt = @step.prompt_body(@context)
    return Result.new(exit_code: 1, stdout: "", stderr: "No prompt content") unless prompt

    prompt = prepend_project_context(prompt)
    prompt = prepend_consumes_context(prompt) if @step.step_type == "skill" && @step.consumes.any?
    prompt = prepend_queryable_context(prompt) if @step.queries.any? && queryable_schemas.any?
    prompt = prepend_failure_context(prompt) if @context["previous_failure"].present? && @step.run_id.present?
    prompt = "#{prompt}\n\n## Additional Context\n\n#{@resolved_input_context}" if @resolved_input_context.present?
    # When the runner handles schemas natively (SDK's StructuredOutput tool
    # injection) we deliberately omit BOTH the schema-shape and the generic
    # produces ```output``` block instructions — otherwise the model follows
    # the prompt and emits text instead of calling the injected tool, leaving
    # structured_output null. produces extraction still works downstream via
    # splice_structured_output.
    if @step.json_schema
      prompt = append_schema_instructions(prompt) unless runner.supports_structured_outputs?
    elsif @step.produces.any?
      prompt = append_produces_instructions(prompt)
    end
    prompt = append_context_projects(prompt) if context_project_paths.any?

    result = runner.execute(**runner_call_kwargs(prompt: prompt, stream: block_given?), &)

    return result unless result.passed?
    return result unless @step.json_schema

    # SDK structured-output path: the runner already enforced the schema
    # upstream (via Claude Agent SDK's `output_format` → `--json-schema`),
    # so the parsed object is sitting on `result.structured_output`. Splice
    # it into stdout as a fenced ```output block so PipelineExtractor + the
    # rest of the pipeline see it via the normal path, and short-circuit
    # the prompt-engineered retry loop.
    return splice_structured_output(result) unless result.structured_output.nil?

    validate_with_session_retry(result, &)
  end

  def splice_structured_output(result)
    produced_var = @step.produces.first
    return result if produced_var.blank?

    block = "```output\n#{produced_var}: #{JSON.generate(result.structured_output)}\n```\n"
    result.with(stdout: [result.stdout.to_s, block].reject(&:empty?).join("\n\n"))
  end

  # self_review: run Claude over the diff with read-only tools and a
  # canned (or operator-overridden) review prompt. Designed to slot
  # between an "implement" skill step and a "pr" step so a draft PR can
  # only be promoted to ready when the review verdict is PASS.
  def execute_self_review(&)
    diff = compute_review_diff
    prompt = build_review_prompt(diff)

    # Force the read-only tool set regardless of step.config["allowed_tools"]
    # — a self-review step that could Write or Edit defeats its own purpose.
    kwargs = runner_call_kwargs(prompt: prompt, stream: block_given?)
    kwargs[:allowed_tools] = SELF_REVIEW_TOOLS

    result = runner.execute(**kwargs, &)
    return result unless result.passed?

    # Same schema-validated short-circuit + retry-loop fallback as
    # execute_skill, so a self_review step can also be schema-bound.
    return result unless @step.json_schema
    return splice_structured_output(result) unless result.structured_output.nil?

    validate_with_session_retry(result, &)
  end

  def compute_review_diff
    base = (@step.config["base_ref"].presence || detect_review_base_ref).to_s
    return "(refusing diff: base_ref #{base.inspect} is not a safe git ref name)" unless base.match?(SAFE_GIT_REF)

    stdout, stderr, status = Open3.capture3(
      "git", "-C", @repo_path, "diff", "--no-color", "#{base}...HEAD", "--"
    )
    return "(could not compute diff against #{base}: #{stderr.strip})" unless status.success?

    truncate_review_diff(stdout)
  end

  def detect_review_base_ref
    ref, _stderr, status = Open3.capture3(
      "git", "-C", @repo_path, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"
    )
    return ref.strip if status.success? && ref.present?

    ["origin/main", "origin/master"].each do |candidate|
      _, _, check = Open3.capture3("git", "-C", @repo_path, "rev-parse", "--verify", "--quiet", candidate)
      return candidate if check.success?
    end

    "HEAD~1"
  end

  def truncate_review_diff(diff)
    return diff if diff.length <= REVIEW_DIFF_MAX_CHARS

    omitted = diff.length - REVIEW_DIFF_MAX_CHARS
    "#{diff.first(REVIEW_DIFF_MAX_CHARS)}\n\n... (diff truncated; #{omitted} more characters omitted)"
  end

  def build_review_prompt(diff)
    focus = @step.config["focus"].presence ||
            "correctness, safety, and adherence to existing patterns"
    produced_var = @step.produces.first.presence || "review"
    intro = if @step.body.present?
              TemplateRenderer.new(@step.body, @context).render
            else
              default_review_intro(focus)
            end

    <<~PROMPT
      #{intro}

      ## Diff

      ```diff
      #{diff}
      ```

      ## Output Required

      At the end of your response, emit your verdict in this format:

      ```output
      #{produced_var}: |
        ## Verdict
        PASS | NEEDS_FIX | BLOCKED

        ## Concerns
        (One per line, or "None.")

        ## Suggestions
        (Optional improvements, may be empty.)
      ```
    PROMPT
  end

  def default_review_intro(focus)
    <<~INTRO.strip
      You are reviewing a proposed code change. Focus on: #{focus}.

      Use the read-only tools (Read, Grep, Glob) to investigate affected
      files for context. You CANNOT make changes — review only.
    INTRO
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
  # Skill/prompt streaming lives in Runners::ClaudeCLI; bash streaming for
  # script/command steps stays here.

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

  # --- Runner dispatch ---

  # Build the kwargs hash passed to `runner.execute`. Centralizes per-step
  # configuration (model, effort, allowed_tools, add_dirs, permission mode)
  # so all runner implementations see a consistent contract.
  def runner_call_kwargs(prompt:, stream:, resume_session_id: nil, resume_message: nil)
    resume_session_id ||= @resume_session_id
    resume_message ||= @resume_message

    {
      prompt: prompt,
      cwd: @repo_path,
      env: env_vars,
      resume_session_id: resume_session_id,
      resume_message: resume_message,
      model: @step.config["model"].presence,
      max_turns: @step.config["max_turns"].presence,
      effort: @step.config["effort"].presence || "medium",
      allowed_tools: resolved_allowed_tools,
      dangerously_skip_permissions: project_for_step&.skip_permissions? || false,
      permission_mode: "dontAsk",
      add_dirs: context_project_paths,
      stream: stream,
      # Schema-validated structured outputs. Only runners that support this
      # contract (today: ClaudeSDK) will consume it; ClaudeCLI ignores it.
      json_schema: @step.json_schema&.parsed_body,
      # Runner-level policy hooks (also SDK-only). Today's only knob is the
      # cwd-confining write hook, default ON. Operators can flip it off
      # globally via Setting["confine_writes_to_cwd"] = "false" or
      # per-step via Step.config["confine_writes_to_cwd"] = false.
      hooks: { "confine_writes_to_cwd" => confine_writes_to_cwd? },
      # Subagent definitions visible to the main agent via the Task tool.
      # Each entry is a hash of AgentDefinition fields (description, prompt,
      # tools, model, ...). SDK-only; ClaudeCLI ignores.
      agents: @step.config["agents"].presence,
      # MCP server registry. Per-step Step.config["mcp_servers"] wins;
      # otherwise fall back to the global Setting. SDK-only.
      mcp_servers: resolved_mcp_servers
    }
  end

  # Per-step config beats the Setting default. Returns nil (not {}) when
  # nothing's configured so the runner can omit the field cleanly from
  # the wire JSON.
  def resolved_mcp_servers
    per_step = @step.config["mcp_servers"]
    return per_step if per_step.is_a?(Hash) && per_step.any?

    global = Setting["mcp_servers"]
    return nil if global.blank?

    parsed = begin
      JSON.parse(global)
    rescue JSON::ParserError
      nil
    end
    parsed.is_a?(Hash) && parsed.any? ? parsed : nil
  end

  def confine_writes_to_cwd?
    if @step.config.key?("confine_writes_to_cwd")
      ActiveModel::Type::Boolean.new.cast(@step.config["confine_writes_to_cwd"])
    else
      raw = Setting["confine_writes_to_cwd"]
      return true if raw.nil?

      ActiveModel::Type::Boolean.new.cast(raw)
    end
  end

  def resolved_allowed_tools
    base = @step.config["allowed_tools"].presence ||
           Setting["default_allowed_tools"].presence ||
           DEFAULT_ALLOWED_TOOLS
    active_queryable_schemas.any? ? "#{base},Bash(seneschal-context:*)" : base
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

  def poll_pr_checks(cfg) # rubocop:disable Metrics/MethodLength
    pr = interpolate_string(cfg.fetch("pr", "${pr_number}"))
    poll_interval = cfg.fetch("poll_interval", 30)
    deadline = Time.current + @step.timeout
    started_at = Time.current
    poll_count = 0

    sleep 5

    loop do
      poll_count += 1
      stdout, _, status = Open3.capture3(
        env_vars,
        "gh", "pr", "checks", pr.to_s, "--json", "name,bucket,link",
        chdir: @repo_path
      )

      checks = if status.success?
                 begin
                   JSON.parse(stdout)
                 rescue StandardError
                   []
                 end
               else
                 []
               end

      if block_given?
        yield({
          output: render_pr_checks_status(
            pr_number: pr, poll: poll_count, started_at: started_at,
            deadline: deadline, checks: checks
          )
        })
      end

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

      return Result.new(exit_code: 1, stdout: stdout.to_s, stderr: "CI checks timed out after #{@step.timeout}s") if Time.current > deadline

      sleep poll_interval
    end
  end

  # Multi-line text used as RunStep#output for an in-flight ci_check (pr
  # mode). The format is consumed both by humans reading the run page and
  # by the `_ci_check_status` partial — keep the first three lines stable
  # so the partial's regex parser keeps working.
  def render_pr_checks_status(pr_number:, poll:, started_at:, deadline:, checks:)
    elapsed = (Time.current - started_at).to_i
    remaining = [(deadline - Time.current).to_i, 0].max
    lines = [
      "Watching CI checks for PR ##{pr_number}",
      "Poll ##{poll} · elapsed #{format_seconds(elapsed)} · times out in #{format_seconds(remaining)}"
    ]

    if checks.any?
      counts = checks.group_by { |c| c["bucket"] }.transform_values(&:size)
      summary = ["pending", "pass", "fail", "skipping"].filter_map do |bucket|
        next if counts[bucket].to_i.zero?

        "#{counts[bucket]} #{bucket}"
      end.join(" · ")
      lines << "Checks: #{summary}"
      lines << ""
      checks.each do |c|
        icon = CHECK_BUCKET_ICONS.fetch(c["bucket"], "❓")
        lines << "#{icon} #{c["name"]}"
      end
    else
      lines << "Checks: none reported yet"
    end

    lines.join("\n")
  end

  def format_seconds(secs)
    return "0s" if secs <= 0

    mins, s = secs.divmod(60)
    mins.positive? ? "#{mins}m #{s}s" : "#{s}s"
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

  def poll_workflow_run(cfg) # rubocop:disable Metrics/MethodLength
    workflow_file = interpolate_string(cfg.fetch("workflow", "ci.yml"))
    ref = interpolate_string(cfg.fetch("ref", "main"))
    should_trigger = cfg.fetch("trigger", false)
    poll_interval = cfg.fetch("poll_interval", 30)
    deadline = Time.current + @step.timeout
    started_at = Time.current
    poll_count = 0

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
      poll_count += 1
      stdout, _, status = Open3.capture3(
        env_vars,
        "gh", "run", "list",
        "--workflow", workflow_file,
        "--branch", ref,
        "--limit", "1",
        "--json", "databaseId,status,conclusion",
        chdir: @repo_path
      )

      runs = if status.success?
               begin
                 JSON.parse(stdout)
               rescue StandardError
                 []
               end
             else
               []
             end
      run_data = runs.is_a?(Array) ? runs.first : nil

      if block_given?
        yield({
          output: render_workflow_run_status(
            workflow_file: workflow_file, ref: ref, poll: poll_count,
            started_at: started_at, deadline: deadline, run_data: run_data
          )
        })
      end

      if run_data && run_data["status"] == "completed"
        if run_data["conclusion"] == "success"
          return Result.new(exit_code: 0, stdout: "Workflow '#{workflow_file}' passed (run ##{run_data["databaseId"]})", stderr: "")
        end

        return Result.new(exit_code: 1,
                          stdout: "Workflow '#{workflow_file}' #{run_data["conclusion"]} (run ##{run_data["databaseId"]})", stderr: "")

      end

      return Result.new(exit_code: 1, stdout: "", stderr: "Workflow timed out after #{@step.timeout}s") if Time.current > deadline

      sleep poll_interval
    end
  end

  def render_workflow_run_status(workflow_file:, ref:, poll:, started_at:, deadline:, run_data:) # rubocop:disable Metrics/ParameterLists
    elapsed = (Time.current - started_at).to_i
    remaining = [(deadline - Time.current).to_i, 0].max
    lines = [
      "Watching GitHub Actions workflow #{workflow_file.inspect} on #{ref}",
      "Poll ##{poll} · elapsed #{format_seconds(elapsed)} · times out in #{format_seconds(remaining)}"
    ]
    if run_data
      lines << "Status: #{run_data["status"]}#{" (#{run_data["conclusion"]})" if run_data["conclusion"]}"
      lines << "Run ##{run_data["databaseId"]}" if run_data["databaseId"]
    else
      lines << "Status: no run reported yet for #{ref}"
    end
    lines.join("\n")
  end

  # --- Helpers ---

  def env_vars
    vars = @context.transform_keys { |k| k.to_s.upcase }.merge(
      "REPO_PATH" => @repo_path
    )
    vars["INPUT_CONTEXT"] = @resolved_input_context if @resolved_input_context.present?
    vars.merge!(queryable_env_vars) if active_queryable_schemas.any?
    vars
  end

  def queryable_env_vars
    {
      "PATH" => "#{Rails.root.join("bin")}:#{ENV.fetch("PATH", "")}",
      "SENESCHAL_DB_PATH" => absolute_db_path,
      "SENESCHAL_RUN_ID" => resolved_run_id.to_s,
      "SENESCHAL_RUN_STEP_ID" => @run_step_id.to_s,
      "SENESCHAL_QUERYABLE_VARS" => active_queryable_schemas.keys.join(",")
    }
  end

  def absolute_db_path
    raw = ActiveRecord::Base.connection_db_config.database.to_s
    Pathname.new(raw).absolute? ? raw : Rails.root.join(raw).to_s
  end

  def resolved_run_id
    return @step.run_id if @step.run_id
    return @resolved_run_id if defined?(@resolved_run_id)

    @resolved_run_id = @run_step_id ? RunStep.where(id: @run_step_id).pick(:run_id) : nil
  end

  def queryable_schemas
    @queryable_schemas ||= begin
      workflow = @step.workflow || @step.run&.workflow
      next_position = @step.position || (workflow ? (workflow.steps.maximum(:position) || 0) + 1 : 1)
      workflow ? Step.queryable_variable_schemas(workflow, next_position) : {}
    end
  end

  def active_queryable_schemas
    @active_queryable_schemas ||= queryable_schemas.slice(*@step.queries)
  end

  def project_for_step
    @project_for_step ||= @step.workflow&.project || @step.run&.workflow&.project
  end

  def prepend_project_context(prompt)
    project = project_for_step
    return prompt if project&.markdown_context.blank?

    <<~CONTEXT + prompt
      ## Project Context

      #{project.markdown_context}

      ---

    CONTEXT
  end

  def prepend_failure_context(prompt)
    step_name = @context["previous_failure_step"] || "previous step"
    round = @context["recovery_round"]
    header = "## Recovery Context (round #{round})\n\nThe step \"#{step_name}\" failed. Here is the output from the failure:\n\n"
    failure = @context["previous_failure"].to_s.truncate(20_000)
    "#{header}```\n#{failure}\n```\n\nUsing the failure information above, complete the following task:\n\n#{prompt}"
  end

  def prepend_consumes_context(prompt)
    blocks = @step.consumes.filter_map do |name|
      value = JsonPathResolver.lookup(@context, name)
      formatted = JsonPathResolver.format(value)
      next if formatted.strip.empty?

      "<#{name}>\n#{formatted}\n</#{name}>"
    end
    return prompt if blocks.empty?

    <<~CONTEXT + prompt
      ## Input Variables

      The workflow has provided the following values for this step. Use them as input:

      #{blocks.join("\n\n")}

      ---

    CONTEXT
  end

  def context_project_paths
    @context_project_paths ||= @step.ready_context_projects.map(&:local_path)
  end

  def append_context_projects(prompt)
    projects = @step.ready_context_projects
    lines = projects.map { |p| "- #{p.name}: #{p.local_path}" }.join("\n")
    prompt + <<~CONTEXT


      ## Available Project Directories

      You also have read access to the following Seneschal project directories for reference. Use them when helpful, but remember the primary working directory is the repo you were launched in.

      #{lines}
    CONTEXT
  end

  # When the step has any consumes marked as queryable, prepend a section
  # listing each queryable variable + its schema, plus instructions for the
  # `seneschal-context` CLI. The actual JSON values stay out of the prompt;
  # the step calls the wrapper with jq expressions when it needs data.
  def prepend_queryable_context(prompt)
    blocks = active_queryable_schemas.map do |var, schema|
      <<~BLOCK
        ### `#{var}` — schema "#{schema.name}"

        ```json
        #{schema.body}
        ```
      BLOCK
    end

    <<~CONTEXT + prompt
      ## Queryable Context

      The variables below are available to this step but their full JSON values are NOT loaded into this prompt. Use the `seneschal-context` CLI tool to pull only what you need:

      ```
      seneschal-context <variable> <jq-expression>
      ```

      Examples:
      - `seneschal-context #{active_queryable_schemas.keys.first} '.title'` — fetch a top-level field
      - `seneschal-context #{active_queryable_schemas.keys.first} 'keys'` — list top-level keys
      - `seneschal-context #{active_queryable_schemas.keys.first} '.items | length'` — count an array
      - `seneschal-context #{active_queryable_schemas.keys.first} '.items[] | select(.kind == "x") | .name'` — filter and project

      Output is whatever jq prints (scalars unquoted-or-quoted by jq, arrays/objects pretty-printed). Each call is logged for the operator to review, so prefer narrow queries over broad dumps.

      Available variables and their schemas:

      #{blocks.join("\n")}
      ---

    CONTEXT
  end

  # When a skill/prompt step has a JSON Schema attached, extract the produced
  # output and validate it. On failure, resume the same Claude session with
  # the schema errors as feedback and ask for a corrected re-emission. Loops
  # up to validation_max_attempts (config default: 3). After exhausting all
  # attempts the step fails with the accumulated errors.
  def validate_with_session_retry(initial_result, &)
    max_attempts = (@step.config["validation_max_attempts"] || 3).to_i
    return initial_result if max_attempts <= 0

    current = initial_result
    attempts = 0

    loop do
      errors = validation_errors_for(current)
      return current if errors.nil?

      attempts += 1
      if attempts >= max_attempts
        return Result.new(
          exit_code: 1,
          stdout: current.stdout,
          stderr: validation_failure_message(errors, attempts),
          stream_events: current.stream_events
        )
      end

      session_id = session_id_from(current)
      unless session_id
        return Result.new(
          exit_code: 1,
          stdout: current.stdout,
          stderr: "JSON Schema validation failed and no Claude session id was captured for retry:\n#{errors.map do |e|
            "  - #{e}"
          end.join("\n")}",
          stream_events: current.stream_events
        )
      end

      feedback = validation_feedback_message(errors)
      current = runner.execute(
        **runner_call_kwargs(prompt: nil, stream: block_given?,
                             resume_session_id: session_id, resume_message: feedback),
        &
      )
      return current unless current.passed?
    end
  end

  def validation_errors_for(result)
    output_var = @step.produces.first
    return ["No output variable configured for schema-bound step"] if output_var.to_s.strip.empty?

    extracted = PipelineExtractor.new(@step, result.stdout).extract
    raw = extracted[output_var]
    return ["Output variable `#{output_var}` was missing from the response"] if raw.nil? || raw.to_s.strip.empty?

    parsed = parse_json_output(raw)
    return parsed[:error] if parsed.is_a?(Hash) && parsed[:error]

    validation = JsonSchemaValidator.new(@step.json_schema).validate(parsed)
    validation[:valid] ? nil : validation[:errors]
  end

  def parse_json_output(raw)
    JSON.parse(raw.to_s)
  rescue JSON::ParserError => e
    output_var = @step.produces.first
    { error: ["Output variable `#{output_var}` was not valid JSON: #{e.message}"] }
  end

  def validation_feedback_message(errors)
    output_var = @step.produces.first.presence || "result"
    bullets = errors.map { |e| "- #{e}" }.join("\n")
    <<~MSG
      The `#{output_var}` JSON you just emitted did not validate against the schema "#{@step.json_schema.name}":

      #{bullets}

      Please re-emit the corrected `#{output_var}` value in the same `output` block format. Include the full JSON, not a summary or status word.
    MSG
  end

  def validation_failure_message(errors, attempts)
    bullets = errors.map { |e| "  - #{e}" }.join("\n")
    "JSON Schema validation failed after #{attempts} attempt#{"s" unless attempts == 1}:\n#{bullets}"
  end

  def session_id_from(result)
    return result.session_id if result.respond_to?(:session_id) && result.session_id.present?

    events = result.stream_events || []
    events.reverse_each do |event|
      sid = event["session_id"]
      return sid if sid
    end
    nil
  end

  def append_schema_instructions(prompt)
    schema = @step.json_schema
    output_var = @step.produces.first.presence || "result"
    prompt + <<~INSTRUCTIONS

      ## Required JSON Output Schema

      This step's only output is a single variable named `#{output_var}` whose value must be valid JSON conforming to the schema "#{schema.name}".

      Emit it at the very end of your response using the multiline output block format:

      ```output
      #{output_var}: |
        { ...JSON conforming to the schema... }
      ```

      The schema:

      ```json
      #{schema.body}
      ```
    INSTRUCTIONS
  end

  def append_produces_instructions(prompt)
    vars = @step.produces.map { |v| "#{v}: <value>" }.join("\n")
    prompt + <<~INSTRUCTIONS

      ## Required Output Variables

      After completing the task, you MUST include an output block at the very end of your response.

      For short values (IDs, numbers, names), use single-line format:
      ```output
      pr_number: 42
      branch_name: feature/my-feature
      ```

      For long values (plans, code, descriptions), use the multiline `|` format:
      ```output
      my_variable: |
        The full content goes here.
        Everything indented with 2 spaces is part of the value.
        Include ALL content — never summarize to "complete" or "done".
      ```

      You MUST produce these variables with their FULL content:
      ```output
      #{vars}
      ```

      CRITICAL: Each value must contain the actual content, not a status word. If a variable should hold a plan, include the entire plan. If it should hold a number, include the number.
    INSTRUCTIONS
  end

  def interpolate_string(str)
    str.to_s.gsub(/\$\{([\w.]+)\}/) do
      path = ::Regexp.last_match(1)
      value = JsonPathResolver.lookup(@context, path)
      value.nil? ? "${#{path}}" : JsonPathResolver.format(value)
    end
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
