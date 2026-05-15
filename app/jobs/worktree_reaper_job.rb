class WorktreeReaperJob < ApplicationJob
  queue_as :default

  def perform
    WorktreeManager.reap_stale(older_than: WorktreeManager.retention_days.days)
  end
end
