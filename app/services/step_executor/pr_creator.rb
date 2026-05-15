require "open3"

class StepExecutor
  # Handles `step_type: "pr"` execution: discovers the current branch, checks
  # whether a PR is already open against it (idempotency), and otherwise calls
  # `gh pr create` with explicit argv. Captures the resulting URL/number and
  # emits ::set-output lines so PipelineExtractor can hand them off to
  # downstream steps as `pr_number`, `pr_url`, and `branch_name`.
  module PrCreator # rubocop:disable Metrics/ModuleLength
    # Strict subset of git's ref-name rules — the branch flows into argv for
    # multiple gh/git commands (including the destructive clean path), so
    # refuse anything that could be mistaken for a flag or that contains a
    # shell metacharacter or `..` segment.
    SAFE_BRANCH_NAME = %r{\A[A-Za-z0-9_][A-Za-z0-9._/-]*\z}

    private

    def execute_pr_step(&) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      cfg = @step.config || {}
      title = interpolate_string(cfg["title"].to_s).strip
      return Result.new(exit_code: 1, stdout: "", stderr: "PR step requires a non-empty title") if title.empty?

      branch = pr_branch_name(cfg)
      return Result.new(exit_code: 1, stdout: "", stderr: "Could not determine current branch for PR step") if branch.blank?
      unless branch.match?(SAFE_BRANCH_NAME)
        return Result.new(exit_code: 1, stdout: "",
                          stderr: "Refusing PR step: branch #{branch.inspect} is not a safe git ref name")
      end

      yield({ output: "Checking for existing PR on #{branch}..." }) if block_given?

      existing_prs = open_prs_for_branch(branch)

      if existing_prs.any?
        return reuse_existing_pr(existing_prs.first, branch, &) unless cfg["clean"]

        err = clean_branch_and_prs(existing_prs, branch, &)
        return err if err
        # Cleaned successfully — fall through to the create flow.

      end

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

    def open_prs_for_branch(branch)
      stdout, _stderr, status = Open3.capture3(
        env_vars,
        "gh", "pr", "list", "--head", branch, "--state", "open",
        "--json", "number,url", "--limit", "50",
        chdir: @repo_path
      )
      return [] unless status.success?

      list = begin
        JSON.parse(stdout)
      rescue JSON::ParserError
        []
      end
      list.is_a?(Array) ? list : []
    end

    # Back-compat shim: returns the first open PR (or nil) for callers that
    # only care about the reuse case.
    def existing_pr_for_branch(branch)
      open_prs_for_branch(branch).first
    end

    # Closes every open PR on this branch (with a Seneschal-generated
    # comment for audit), wipes the remote branch, and pushes the local
    # branch fresh. Returns nil on success, a Result on the first failure.
    # The order is deliberate — PRs first so GitHub doesn't try to update
    # them when the underlying ref disappears; remote branch second so the
    # subsequent push creates a clean ref; then the local push.
    def clean_branch_and_prs(existing_prs, branch, &)
      err = close_existing_prs(existing_prs, branch, &)
      return err if err

      wipe_remote_branch(branch, &) # best-effort — fine if the ref's already gone
      push_local_branch(branch, &)
    end

    def close_existing_prs(prs, branch)
      comment = clean_close_comment
      prs.each do |pr|
        pr_number = pr["number"].to_s
        yield({ output: "Closing existing PR ##{pr_number} on #{branch}..." }) if block_given?

        stdout, stderr, status = Open3.capture3(
          env_vars,
          "gh", "pr", "close", pr_number, "--comment", comment,
          chdir: @repo_path
        )
        unless status.success?
          return Result.new(
            exit_code: status.exitstatus || 1,
            stdout: stdout,
            stderr: "Failed to close PR ##{pr_number}: #{stderr.strip}"
          )
        end
      end
      nil
    end

    # Best-effort. If the remote ref doesn't exist git exits non-zero with
    # "remote ref does not exist" — that's the desired end state, so we
    # don't propagate the failure. Other failures (permissions, network)
    # surface only as a Rails.logger.info; the subsequent `git push -u`
    # will fail loudly enough on its own.
    def wipe_remote_branch(branch)
      yield({ output: "Wiping remote branch origin/#{branch}..." }) if block_given?
      _stdout, stderr, status = Open3.capture3(
        env_vars,
        "git", "push", "--delete", "origin", branch,
        chdir: @repo_path
      )
      return if status.success?

      Rails.logger.info(
        "PrCreator: git push --delete origin #{branch} returned " \
        "#{status.exitstatus}: #{stderr.strip}"
      )
    end

    def push_local_branch(branch)
      yield({ output: "Pushing local #{branch} to origin..." }) if block_given?
      stdout, stderr, status = Open3.capture3(
        env_vars,
        "git", "push", "-u", "origin", branch,
        chdir: @repo_path
      )
      return nil if status.success?

      Result.new(
        exit_code: status.exitstatus || 1,
        stdout: stdout,
        stderr: "Failed to push local #{branch}: #{stderr.strip}"
      )
    end

    # The comment left on each closed PR so reviewers can trace the
    # supersession back to a specific Seneschal run.
    def clean_close_comment
      run_id = resolved_run_id
      if run_id
        "Superseded by Seneschal run ##{run_id} — re-running with `clean: true`."
      else
        "Superseded by Seneschal — re-running with `clean: true`."
      end
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
