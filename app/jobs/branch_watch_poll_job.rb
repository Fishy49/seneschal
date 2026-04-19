# Runs every 15 minutes. For each task watching a GitHub branch, fetches the
# current HEAD SHA of that branch via `git ls-remote` and enqueues a run if
# it has changed since we last saw it. The very first poll after a task is
# configured just records the current SHA ("arming" the watcher) so that
# turning on the trigger doesn't immediately fire.
class BranchWatchPollJob < ApplicationJob
  queue_as :default

  def perform
    PipelineTask.branch_watching.find_each do |task|
      poll_one(task)
    rescue StandardError => e
      Rails.logger.error("BranchWatchPollJob failed for task #{task.id}: #{e.class}: #{e.message}")
    end
  end

  private

  def poll_one(task)
    url = task.watched_repo_url
    branch = task.watched_branch
    return if url.blank? || branch.blank?

    current_sha = GitRemote.head_sha(url, branch)
    return if current_sha.blank?

    last_sha = task.last_seen_sha

    if last_sha.blank?
      task.record_seen_sha!(current_sha)
      return
    end

    return if current_sha == last_sha

    if task.executable?
      task.enqueue_run!(reason: "branch_update")
    else
      Rails.logger.info(
        "BranchWatchPollJob skipping task #{task.id}: not executable " \
        "(status=#{task.status}, workflow=#{task.workflow_id.inspect})"
      )
    end
    task.record_seen_sha!(current_sha)
  end
end
