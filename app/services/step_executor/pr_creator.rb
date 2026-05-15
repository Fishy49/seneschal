require "open3"

class StepExecutor
  # Handles `step_type: "pr"` execution: discovers the current branch, checks
  # whether a PR is already open against it (idempotency), and otherwise calls
  # `gh pr create` with explicit argv. Captures the resulting URL/number and
  # emits ::set-output lines so PipelineExtractor can hand them off to
  # downstream steps as `pr_number`, `pr_url`, and `branch_name`.
  module PrCreator # rubocop:disable Metrics/ModuleLength
    private

    def execute_pr_step(&)
      cfg = @step.config || {}
      title = interpolate_string(cfg["title"].to_s).strip
      return Result.new(exit_code: 1, stdout: "", stderr: "PR step requires a non-empty title") if title.empty?

      branch = pr_branch_name(cfg)
      return Result.new(exit_code: 1, stdout: "", stderr: "Could not determine current branch for PR step") if branch.blank?

      yield({ output: "Checking for existing PR on #{branch}..." }) if block_given?

      existing = existing_pr_for_branch(branch)
      return reuse_existing_pr(existing, branch, &) if existing

      base = interpolate_string(cfg.fetch("base", "main").to_s).strip
      base = "main" if base.empty?
      body = interpolate_string(cfg["body"].to_s)
      draft = cfg.fetch("draft", true)

      argv = build_pr_create_argv(title: title, body: body, base: base, draft: draft, cfg: cfg)
      yield({ output: "Creating PR via #{argv.first(3).join(" ")}..." }) if block_given?

      stdout, stderr, status = Open3.capture3(env_vars, *argv, chdir: @repo_path)
      unless status.success?
        return Result.new(exit_code: status.exitstatus || 1, stdout: stdout, stderr: stderr.presence || "gh pr create failed")
      end

      pr_url = extract_pr_url(stdout)
      pr_number = extract_pr_number(pr_url)
      if pr_number.blank?
        return Result.new(
          exit_code: 1, stdout: stdout, stderr: "Could not parse PR URL from gh output:\n#{stdout}"
        )
      end

      Result.new(
        exit_code: 0,
        stdout: pr_outputs_block(pr_number: pr_number, pr_url: pr_url, branch: branch, raw: stdout),
        stderr: stderr
      )
    rescue StandardError => e
      Result.new(exit_code: 1, stdout: "", stderr: e.message)
    end

    # --- helpers ---

    def pr_branch_name(cfg)
      explicit = interpolate_string(cfg["branch"].to_s).strip if cfg["branch"].present?
      return explicit if explicit.present?

      stdout, _stderr, status = Open3.capture3(
        env_vars, "git", "rev-parse", "--abbrev-ref", "HEAD",
        chdir: @repo_path
      )
      status.success? ? stdout.strip : nil
    end

    def existing_pr_for_branch(branch)
      stdout, _stderr, status = Open3.capture3(
        env_vars,
        "gh", "pr", "list", "--head", branch, "--state", "open",
        "--json", "number,url", "--limit", "1",
        chdir: @repo_path
      )
      return nil unless status.success?

      list = begin
        JSON.parse(stdout)
      rescue JSON::ParserError
        []
      end
      list.is_a?(Array) ? list.first : nil
    end

    def reuse_existing_pr(existing, branch)
      pr_url = existing["url"].to_s
      pr_number = existing["number"].to_s
      yield({ output: "PR ##{pr_number} already exists for #{branch}: #{pr_url}" }) if block_given?

      Result.new(
        exit_code: 0,
        stdout: pr_outputs_block(
          pr_number: pr_number, pr_url: pr_url, branch: branch,
          raw: "Reusing existing PR ##{pr_number}: #{pr_url}"
        ),
        stderr: ""
      )
    end

    def build_pr_create_argv(title:, body:, base:, draft:, cfg:)
      argv = ["gh", "pr", "create", "--title", title, "--body", body, "--base", base]
      argv << "--draft" if draft

      Array(cfg["reviewers"]).map(&:to_s).reject(&:empty?).each do |r|
        argv << "--reviewer" << r
      end
      Array(cfg["labels"]).map(&:to_s).reject(&:empty?).each do |l|
        argv << "--label" << l
      end
      Array(cfg["assignees"]).map(&:to_s).reject(&:empty?).each do |a|
        argv << "--assignee" << a
      end

      argv
    end

    # gh pr create prints the new PR URL to stdout. There can be other lines
    # (warnings, hints), so scan rather than assume the URL is the whole output.
    def extract_pr_url(stdout)
      stdout.to_s.lines.reverse_each do |line|
        match = line.strip.match(%r{https?://[^\s]*/pull/\d+})
        return match[0] if match
      end
      nil
    end

    def extract_pr_number(url)
      return nil if url.blank?

      m = url.match(%r{/pull/(\d+)})
      m && m[1]
    end

    # PipelineExtractor parses ::set-output for non-AI steps. Reuse that path
    # by emitting the conventional outputs to stdout. The raw gh output is
    # echoed below for human consumption / debugging in the run UI.
    def pr_outputs_block(pr_number:, pr_url:, branch:, raw:)
      <<~OUT.strip
        ::set-output pr_number=#{pr_number}
        ::set-output pr_url=#{pr_url}
        ::set-output branch_name=#{branch}

        #{raw}
      OUT
    end
  end
end
