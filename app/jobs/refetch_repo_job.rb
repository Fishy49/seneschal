require "open3"

# Refresh a Project's canonical clone by pulling the latest tip of the
# default branch from origin. Triggered from the project show page; lets
# operators force a sync without waiting for the next run to do its
# WorktreeManager fetch.
#
# Behavior depends on what's currently checked out in the canonical clone:
#   - HEAD on default branch    → hard reset to origin/<default>
#   - HEAD anywhere else        → update-ref the local default branch
#                                  to origin/<default> without disturbing
#                                  HEAD (so we never trip git's "branch
#                                  is checked out in a worktree" guard)
class RefetchRepoJob < ApplicationJob
  queue_as :default

  def perform(project)
    return unless project.repo_ready?

    update_status(project, "refetching")

    return unless step_ok?(project, "fetch",
                           "git", "-C", project.local_path, "fetch", "--prune", "origin")

    default = WorktreeManager.default_branch_name(project) || "main"

    sync_cmd = if head_on_branch?(project, default)
                 ["git", "-C", project.local_path, "reset", "--hard", "origin/#{default}"]
               else
                 # HEAD is elsewhere; update the local branch ref without
                 # disturbing whatever's checked out in the canonical clone
                 # (avoids tripping git's "branch is checked out in a worktree" guard).
                 ["git", "-C", project.local_path,
                  "update-ref", "refs/heads/#{default}", "origin/#{default}"]
               end

    return unless step_ok?(project, "sync", *sync_cmd)

    update_status(project, "ready")
  rescue StandardError => e
    Rails.logger.error("Refetch crashed for #{project.name}: #{e.message}")
    update_status(project, "error")
  end

  private

  def head_on_branch?(project, branch)
    stdout, _stderr, status = Open3.capture3(
      "git", "-C", project.local_path, "symbolic-ref", "--short", "HEAD"
    )
    status.success? && stdout.strip == branch
  end

  def step_ok?(project, label, *cmd)
    _, stderr, status = Open3.capture3(*cmd)
    return true if status.success?

    Rails.logger.error("Refetch #{label} failed for #{project.name}: #{stderr.strip}")
    update_status(project, "error")
    false
  end

  def update_status(project, status)
    project.update!(repo_status: status)
    Turbo::StreamsChannel.broadcast_replace_to(
      project,
      target: "repo_status",
      partial: "projects/repo_status",
      locals: { project: project }
    )
  end
end
