require "open3"

# Allocates an isolated git worktree for each Run so concurrent runs on the
# same project don't corrupt each other's working tree, and so a failed run's
# state can be inspected without blocking the next run.
#
# Each worktree lives under Setting["worktree_root"] (default tmp/worktrees)
# at <root>/<run_id>/ and is checked out on a deterministic branch named
# `seneschal/run-<run_id>[-<task-slug>]` branched off the project's currently-
# checked-out branch HEAD. The branch name is computed at allocate-time from
# Run#id + the parameterized PipelineTask title (when present) and persisted
# to `runs.branch_name` so cleanup + downstream PR steps see the exact same
# string the worktree was created with — even if the task title is renamed
# mid-flight. Worktrees share the project's git object database, so branches
# and commits made in the worktree are visible from the canonical clone after
# the fact.
#
# Lifecycle:
#   - allocate(run): creates the worktree and the branch, stamps run.worktree_path
#   - cleanup(run): removes the worktree and its branch (called on success)
#   - retain(run): marks the worktree as retained-for-forensics (failure/stop)
#   - reap_stale(older_than:): removes retained worktrees past the retention window
class WorktreeManager
  class WorktreeError < StandardError; end

  BRANCH_PREFIX = "seneschal/run-".freeze
  SLUG_MAX_LENGTH = 40
  DEFAULT_RETENTION_DAYS = 7

  class << self
    def allocate(run)
      project = run.workflow.project
      raise WorktreeError, "Project #{project.id} is not ready" unless project.repo_ready?

      target = path_for(run)
      FileUtils.mkdir_p(File.dirname(target))

      # Best-effort fetch so origin/HEAD reflects the remote's current default
      # branch tip. We deliberately branch the new worktree off the remote ref
      # (not the local working-tree HEAD) so allocate is independent of whatever
      # state project.local_path is currently checked out on. No operator-run
      # prep step required.
      _, fetch_err, fetch_status = Open3.capture3(
        "git", "-C", project.local_path, "fetch", "--prune", "origin"
      )
      unless fetch_status.success?
        Rails.logger.info(
          "WorktreeManager: fetch failed for project #{project.id} " \
          "(#{fetch_err.strip}); using local refs only"
        )
      end

      start_point = detect_start_point(project)
      branch = ensure_branch_name(run)

      _stdout, stderr, status = Open3.capture3(
        "git", "-C", project.local_path,
        "worktree", "add", target, "-b", branch, start_point
      )
      raise WorktreeError, "git worktree add failed: #{stderr.strip}" unless status.success?

      run.update!(worktree_path: target, worktree_retained: false)
      target
    end

    # Default branch as a bare name (e.g. "main"), derived from origin/HEAD
    # when available. Returns nil if no remote info exists — callers should
    # decide on their own fallback (typically "main"). Used by callers that
    # want to `git checkout <name>` rather than branch off a remote ref.
    def default_branch_name(project)
      start = detect_start_point(project)
      return nil if start == "HEAD"

      start.delete_prefix("origin/")
    end

    # Resolve the commit-ish to branch the new worktree off of. Prefers the
    # remote's default branch (origin/HEAD) so legacy state in project.local_path
    # is irrelevant. Falls back to common conventions and finally to local HEAD
    # so tests against bare local repos (no remote) still work.
    def detect_start_point(project)
      stdout, _stderr, status = Open3.capture3(
        "git", "-C", project.local_path,
        "symbolic-ref", "--short", "refs/remotes/origin/HEAD"
      )
      return stdout.strip if status.success? && stdout.present?

      ["origin/main", "origin/master"].each do |ref|
        _, _, check = Open3.capture3(
          "git", "-C", project.local_path, "rev-parse", "--verify", "--quiet", ref
        )
        return ref if check.success?
      end

      "HEAD"
    end

    # Reuse an existing worktree if one is already allocated and present on
    # disk; otherwise allocate a fresh one. Used by ExecuteRunJob to handle
    # resume / after-approval flows transparently.
    def ensure_for(run)
      if run.worktree_path.present? && File.directory?(run.worktree_path)
        run.update!(worktree_retained: false) if run.worktree_retained?
        return run.worktree_path
      end
      allocate(run)
    end

    def cleanup(run)
      return if run.worktree_path.blank?

      project = run.workflow.project
      remove_worktree(project.local_path, run.worktree_path) if File.directory?(run.worktree_path)
      # Prune stale worktree metadata before deleting the branch. If
      # remove_worktree fell back to rm_rf the metadata still says the branch
      # is checked out, and `branch -D` would refuse.
      Open3.capture3("git", "-C", project.local_path, "worktree", "prune")
      delete_branch(project.local_path, branch_for(run))
      run.update!(worktree_path: nil, worktree_retained: false)
    end

    def retain(run)
      run.update!(worktree_retained: true) if run.worktree_path.present?
    end

    def reap_stale(older_than: DEFAULT_RETENTION_DAYS.days)
      cutoff = older_than.ago
      Run.where(worktree_retained: true)
         .where.not(worktree_path: nil)
         .where("COALESCE(finished_at, updated_at) < ?", cutoff)
         .find_each do |run|
        cleanup(run)
      rescue StandardError => e
        Rails.logger.warn("WorktreeReaper: failed to clean run #{run.id}: #{e.class}: #{e.message}")
      end
    end

    def path_for(run)
      File.join(worktree_root, run.id.to_s)
    end

    # Returns the worktree branch name for `run`. Reads `runs.branch_name`
    # when persisted (every run allocated after the
    # AddBranchNameToRuns migration). Falls back to the legacy
    # id-only formula for pre-migration runs so cleanup of historical
    # worktrees keeps working.
    def branch_for(run)
      run.branch_name.presence || legacy_branch_name(run)
    end

    # Computes-and-persists the branch name. Idempotent: returns the existing
    # `branch_name` when the run already has one (resumes, re-allocations after
    # a worktree was reaped) so the same physical branch on disk is always
    # referenced by the same string.
    def ensure_branch_name(run)
      return run.branch_name if run.branch_name.present?

      name = compute_branch_name(run)
      run.update!(branch_name: name)
      name
    end

    # `seneschal/run-<id>[-<slugified-task-title>]`. The slug, when present,
    # is `String#parameterize`'d (ASCII kebab-case), capped at SLUG_MAX_LENGTH,
    # and stripped of any trailing hyphen left over from truncation. Returns
    # the id-only form when no PipelineTask is attached or its title slugs
    # to an empty string (e.g. emoji-only).
    def compute_branch_name(run)
      base = legacy_branch_name(run)
      slug = slugify(run.pipeline_task&.title)
      slug.present? ? "#{base}-#{slug}" : base
    end

    def slugify(title)
      return nil if title.blank?

      slug = title.to_s.parameterize
      return nil if slug.blank?

      slug.first(SLUG_MAX_LENGTH).sub(/-+\z/, "").presence
    end

    def worktree_root
      Setting["worktree_root"].presence || Rails.root.join("tmp/worktrees").to_s
    end

    def retention_days
      raw = Setting["worktree_retention_days"]
      raw.present? ? raw.to_i : DEFAULT_RETENTION_DAYS
    end

    private

    def legacy_branch_name(run)
      "#{BRANCH_PREFIX}#{run.id}"
    end

    def remove_worktree(repo_path, worktree_path)
      _stdout, stderr, status = Open3.capture3(
        "git", "-C", repo_path, "worktree", "remove", "--force", worktree_path
      )
      return if status.success?

      # Worktree command failed — fall back to removing the directory ourselves
      # and let `worktree prune` clean the metadata afterwards.
      Rails.logger.warn("WorktreeManager: git worktree remove failed (#{stderr.strip}); rm -rf'ing #{worktree_path}")
      FileUtils.rm_rf(worktree_path)
    end

    def delete_branch(repo_path, branch)
      _stdout, _stderr, _status = Open3.capture3(
        "git", "-C", repo_path, "branch", "-D", branch
      )
      # Branch may not exist (e.g. step deleted it). Swallow.
    end
  end
end
