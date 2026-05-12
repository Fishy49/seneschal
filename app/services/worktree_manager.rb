require "open3"

# Allocates an isolated git worktree for each Run so concurrent runs on the
# same project don't corrupt each other's working tree, and so a failed run's
# state can be inspected without blocking the next run.
#
# Each worktree lives under Setting["worktree_root"] (default tmp/worktrees)
# at <root>/<run_id>/ and is checked out on a deterministic branch named
# `seneschal/run-<run_id>` branched off the project's currently-checked-out
# branch HEAD. Worktrees share the project's git object database, so
# branches and commits made in the worktree are visible from the canonical
# clone after the fact.
#
# Lifecycle:
#   - allocate(run): creates the worktree and the branch, stamps run.worktree_path
#   - cleanup(run): removes the worktree and its branch (called on success)
#   - retain(run): marks the worktree as retained-for-forensics (failure/stop)
#   - reap_stale(older_than:): removes retained worktrees past the retention window
class WorktreeManager
  class WorktreeError < StandardError; end

  BRANCH_PREFIX = "seneschal/run-".freeze
  DEFAULT_RETENTION_DAYS = 7

  class << self
    def allocate(run)
      project = run.workflow.project
      raise WorktreeError, "Project #{project.id} is not ready" unless project.repo_ready?

      target = path_for(run)
      FileUtils.mkdir_p(File.dirname(target))

      branch = branch_for(run)
      _stdout, stderr, status = Open3.capture3(
        "git", "-C", project.local_path,
        "worktree", "add", target, "-b", branch
      )
      raise WorktreeError, "git worktree add failed: #{stderr.strip}" unless status.success?

      run.update!(worktree_path: target, worktree_retained: false)
      target
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
      delete_branch(project.local_path, branch_for(run))
      Open3.capture3("git", "-C", project.local_path, "worktree", "prune")
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

    def branch_for(run)
      "#{BRANCH_PREFIX}#{run.id}"
    end

    def worktree_root
      Setting["worktree_root"].presence || Rails.root.join("tmp/worktrees").to_s
    end

    def retention_days
      raw = Setting["worktree_retention_days"]
      raw.present? ? raw.to_i : DEFAULT_RETENTION_DAYS
    end

    private

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
