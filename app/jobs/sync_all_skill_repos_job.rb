# Enqueues SyncSkillRepoJob for every enabled SkillRepo. Periodically invoked
# by the recurring schedule so external skill repos stay current without
# operator action.
class SyncAllSkillReposJob < ApplicationJob
  queue_as :default

  def perform
    SkillRepo.enabled.find_each do |repo|
      SyncSkillRepoJob.perform_later(repo.id)
    end
  end
end
