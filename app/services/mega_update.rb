require "open3"

# One-shot post-deploy data migration + cleanup for the agent-runtime refactor.
# Designed to be run once after `db:migrate` on a fresh deploy, and safe to
# re-run any time afterwards (idempotent).
#
# What it does, in order:
#   1. Sanity check — refuses to run when active, fresh runs are in flight
#      (status=pending / awaiting_approval, or status=running with a recent
#      heartbeat). Operator should drain those first.
#   2. Fail hung runs — anything in status=running with no heartbeat for
#      `stale_minutes` (default 30) gets marked failed, its still-running
#      RunSteps get marked failed, the parent PipelineTask gets synced to
#      failed, and its worktree is retained for forensics (the nightly
#      reaper will clean it up later).
#   3. Fail orphan RunSteps — any RunStep stuck in `running` while its
#      parent Run is already in a terminal state (failed/stopped/completed).
#      Leftover from before the recovery path properly cascaded.
#   4. Convert legacy `git checkout <main>` workflow steps — Step rows
#      whose body is the pre-worktree-era `git checkout main && git pull`
#      pattern (or master/trunk variant) get rewritten as documented
#      no-ops. Their body would otherwise fail inside the per-run
#      worktree because the canonical clone already has the default
#      branch checked out. Idempotent — skips bodies already converted.
#   5. Prepare projects — `git checkout <default-branch> && git pull --ff-only`
#      on each ready project's local_path. Normalizes the canonical clone
#      back to a clean state for the out-of-band consumers (CLAUDE.md
#      reader, code maps, context_projects).
#   6. Export skills — materializes legacy DB-backed Skills as filesystem
#      SKILL.md folders via SkillExporter. Skip with skip_skill_export: true.
#
# All steps emit progress lines to the configured io (defaults to $stdout).
# Pass io: a StringIO to capture for tests.
class MegaUpdate
  Summary = Data.define(
    :aborted,
    :hung_runs_failed,
    :orphan_run_steps_failed,
    :legacy_steps_converted,
    :legacy_steps_skipped,
    :projects_prepared,
    :skills_exported,
    :skills_skipped,
    :errors
  )

  DEFAULT_STALE_MINUTES = 30

  # Matches Step bodies that are *only* the pre-worktree-era refresh-main
  # pattern, with no surrounding script. Conservative on purpose: bodies
  # that wrap `git checkout main` inside larger logic are left alone for
  # operator review.
  LEGACY_PULL_MAIN_RE = /\A\s*git\s+checkout\s+(?:main|master|trunk)(?:\s*&&\s*git\s+pull(?:\s+--ff-only)?)?\s*\z/

  CONVERTED_MARKER = "# Auto-converted by seneschal:mega_update".freeze

  def self.call(**)
    new(**).call
  end

  def initialize(dry_run: false, stale_minutes: DEFAULT_STALE_MINUTES, skip_skill_export: false, io: $stdout)
    @dry_run = dry_run
    @stale_minutes = stale_minutes
    @skip_skill_export = skip_skill_export
    @io = io
    @counts = {
      hung_runs_failed: 0,
      orphan_run_steps_failed: 0,
      legacy_steps_converted: 0,
      legacy_steps_skipped: 0,
      projects_prepared: 0,
      skills_exported: 0,
      skills_skipped: 0,
      errors: 0
    }
  end

  def call
    header
    return finalize(aborted: true) if abort_due_to_active_runs?

    fail_hung_runs
    fail_orphan_run_steps
    convert_legacy_pull_main_steps
    prepare_projects
    export_skills unless @skip_skill_export

    finalize(aborted: false)
  end

  private

  def header
    say "=== Seneschal mega-update ==="
    say "  mode:           #{@dry_run ? "DRY RUN — no changes will be made" : "EXECUTE"}"
    say "  stale window:   #{@stale_minutes} minutes"
    say "  skill export:   #{@skip_skill_export ? "SKIPPED" : "included"}"
    say ""
  end

  def abort_due_to_active_runs?
    pending = Run.where(status: "pending").count
    awaiting = Run.where(status: "awaiting_approval").count
    fresh = Run.where(status: "running").where(updated_at: @stale_minutes.minutes.ago..).count

    return false if pending.zero? && awaiting.zero? && fresh.zero?

    say "ABORT — active runs in flight:"
    say "  pending:                       #{pending}"
    say "  awaiting_approval:             #{awaiting}"
    say "  running (heartbeat <#{@stale_minutes}m old):  #{fresh}"
    say ""
    say "Drain these first — let them complete, stop them via the UI, or wait"
    say "until heartbeats go stale — and re-run."
    true
  end

  def fail_hung_runs
    hung = Run.where(status: "running").where(updated_at: ..@stale_minutes.minutes.ago)
    say "[1/5] Fail hung runs (status=running, no heartbeat for >#{@stale_minutes}m)"

    if hung.none?
      say "  ok — none found"
      say ""
      return
    end

    hung.find_each do |run|
      age = ((Time.current - run.updated_at) / 60).round
      label = "Run ##{run.id} (#{run.workflow.project.name} / #{run.workflow.name}) — last heartbeat #{age}m ago"
      say "  #{@dry_run ? "(would fail)" : "failing"} #{label}"
      next if @dry_run

      run.run_steps.where(status: "running").find_each do |rs|
        rs.update!(
          status: "failed",
          finished_at: Time.current,
          duration: rs.started_at ? (Time.current - rs.started_at) : nil,
          error_output: append_note(rs.error_output, "mega_update: hung >#{@stale_minutes}m, auto-failed.")
        )
      end

      run.update!(
        status: "failed",
        finished_at: Time.current,
        error_message: "Run hung in 'running' for >#{@stale_minutes} minutes; auto-failed by seneschal:mega_update."
      )

      WorktreeManager.retain(run) if run.worktree_path.present?
      run.pipeline_task&.update!(status: "failed")
      @counts[:hung_runs_failed] += 1
    rescue StandardError => e
      @counts[:errors] += 1
      say "    ERROR: #{e.class}: #{e.message}"
    end

    say ""
  end

  def fail_orphan_run_steps
    say "[2/5] Fail orphan RunSteps (parent run terminal, RunStep still 'running')"

    orphans = RunStep.where(status: "running").joins(:run).where.not(run: { status: "running" })

    if orphans.none?
      say "  ok — none found"
      say ""
      return
    end

    orphans.includes(:step, :run).find_each do |rs|
      label = "RunStep ##{rs.id} (run ##{rs.run_id}/#{rs.run.status}) #{rs.step&.name}"
      say "  #{@dry_run ? "(would fail)" : "failing"} #{label}"
      next if @dry_run

      rs.update!(
        status: "failed",
        finished_at: rs.finished_at || rs.run.finished_at || rs.updated_at,
        duration: rs.started_at && rs.finished_at ? (rs.finished_at - rs.started_at) : nil,
        error_output: append_note(rs.error_output, "mega_update: parent run was #{rs.run.status} but RunStep stayed running.")
      )
      @counts[:orphan_run_steps_failed] += 1
    rescue StandardError => e
      @counts[:errors] += 1
      say "    ERROR: #{e.class}: #{e.message}"
    end

    say ""
  end

  def convert_legacy_pull_main_steps
    say "[3/5] Convert legacy `git checkout main` workflow steps to no-ops"

    # SQL pre-filter to narrow the candidate set, then strict-regex match
    # in Ruby so we only touch bodies that are exactly the legacy pattern.
    candidates = Step.where(step_type: ["command", "script"])
                     .where("body LIKE ? OR body LIKE ? OR body LIKE ?",
                            "%git checkout main%", "%git checkout master%", "%git checkout trunk%")

    if candidates.none?
      say "  ok — none found"
      say ""
      return
    end

    candidates.find_each do |step|
      raw = step.body.to_s

      # Marker check first — a previously-converted body keeps the original
      # legacy text as a comment, so it still passes the SQL pre-filter but
      # no longer matches the strict regex.
      if raw.lstrip.start_with?(CONVERTED_MARKER)
        say "  skip   Step ##{step.id} (#{step_label(step)}) — already converted"
        @counts[:legacy_steps_skipped] += 1
        next
      end

      next unless LEGACY_PULL_MAIN_RE.match?(raw)

      label = "Step ##{step.id} (#{step_label(step)})"
      if @dry_run
        say "  (would convert) #{label}: #{raw.strip.inspect}"
        next
      end

      original_body = raw
      new_name = step.name.include?("legacy no-op") ? step.name : "#{step.name} (legacy no-op)"
      step.update!(name: new_name, body: converted_step_body(original_body))
      say "  converted #{label}"
      @counts[:legacy_steps_converted] += 1
    rescue StandardError => e
      @counts[:errors] += 1
      say "  ERROR  Step ##{step.id}: #{e.class}: #{e.message}"
    end

    say ""
  end

  def step_label(step)
    "#{step.workflow.name} › #{step.name}"
  end

  # No-op replacement body. First line is the marker we check on idempotent
  # re-runs; the original body is preserved as a comment for audit.
  def converted_step_body(original_body)
    original_inline = original_body.strip.lines.first(3).map { |l| "#   #{l.rstrip}" }.join("\n")
    <<~BASH.strip
      #{CONVERTED_MARKER} on #{Time.current.utc.iso8601}.
      # The original body fails inside the per-run worktree because the
      # canonical clone already has the default branch checked out. The
      # worktree-isolation refactor starts every run on a fresh branch off
      # origin/HEAD, so the explicit pull is redundant. Kept as a no-op so
      # historical RunStep records still render with a step name.
      #
      # Original body:
      #{original_inline}
      true
    BASH
  end

  def prepare_projects
    say "[4/5] Normalize project local_paths (checkout default branch + pull --ff-only)"

    projects = Project.where(repo_status: "ready")
    if projects.none?
      say "  ok — no ready projects"
      say ""
      return
    end

    projects.find_each do |project|
      unless project.local_path_exists?
        say "  skip   #{project.name}: local_path missing (#{project.local_path})"
        next
      end
      # Defensive: `git -C <path>` walks UP the directory tree if <path> isn't
      # itself a git repo, which would mean we'd act on a parent repo by
      # accident. Require .git/ at the exact path.
      unless File.exist?(File.join(project.local_path, ".git"))
        say "  skip   #{project.name}: no .git at #{project.local_path}"
        next
      end

      default_branch = detect_default_branch(project)
      label = "#{project.name} → #{default_branch}"

      if @dry_run
        say "  (would prepare) #{label}"
        next
      end

      _, checkout_err, checkout_status = Open3.capture3(
        "git", "-C", project.local_path, "checkout", default_branch
      )
      unless checkout_status.success?
        say "  fail   #{label}: checkout failed: #{checkout_err.strip}"
        @counts[:errors] += 1
        next
      end

      Open3.capture3("git", "-C", project.local_path, "pull", "--ff-only")
      say "  ready  #{label}"
      @counts[:projects_prepared] += 1
    rescue StandardError => e
      @counts[:errors] += 1
      say "  ERROR  #{project.name}: #{e.class}: #{e.message}"
    end

    say ""
  end

  def export_skills
    say "[5/5] Export DB-backed Skills to filesystem SKILL.md folders"

    skills = Skill.where(skill_repo_id: nil) # don't touch repo-indexed skills
    if skills.none?
      say "  ok — no skills to consider"
      say ""
      return
    end

    skills.find_each do |skill|
      if @dry_run
        say "  (would export) #{skill.display_name}"
        next
      end

      result = SkillExporter.call(skill)
      case result.status
      when :exported
        say "  exported #{skill.display_name} → #{result.path}"
        @counts[:skills_exported] += 1
      when :skipped
        say "  skip     #{skill.display_name} (already on disk)"
        @counts[:skills_skipped] += 1
      when :skipped_group
        say "  skip     #{skill.display_name} (group-scoped — migrate manually)"
        @counts[:skills_skipped] += 1
      end
    rescue StandardError => e
      @counts[:errors] += 1
      say "  ERROR    #{skill.display_name}: #{e.class}: #{e.message}"
    end

    say ""
  end

  def finalize(aborted:)
    say "=== Summary ==="
    if aborted
      say "  ABORTED — no changes made"
    else
      say "  hung runs failed:           #{@counts[:hung_runs_failed]}"
      say "  orphan RunSteps failed:     #{@counts[:orphan_run_steps_failed]}"
      say "  legacy steps converted:     #{@counts[:legacy_steps_converted]}"
      say "  legacy steps already no-op: #{@counts[:legacy_steps_skipped]}"
      say "  projects prepared:          #{@counts[:projects_prepared]}"
      say "  skills exported:            #{@counts[:skills_exported]}"
      say "  skills already on disk:     #{@counts[:skills_skipped]}"
      say "  errors:                     #{@counts[:errors]}"
      say ""
      unless @dry_run
        say "Next steps (optional, on demand):"
        say "  - Register external skill repos via /skill_repos UI or"
        say "    bin/rails 'seneschal:skill_repos:add[<url>,<name>,<branch>]'"
        say "  - Run a small test workflow to verify the deploy"
      end
    end

    Summary.new(aborted: aborted, **@counts)
  end

  def detect_default_branch(project)
    WorktreeManager.default_branch_name(project) || "main"
  end

  def append_note(existing, note)
    [existing, note].compact.map(&:to_s).reject(&:empty?).join("\n").strip
  end

  def say(msg)
    @io.puts(msg)
  end
end
