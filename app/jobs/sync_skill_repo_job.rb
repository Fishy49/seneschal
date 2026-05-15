class SyncSkillRepoJob < ApplicationJob
  queue_as :default

  def perform(skill_repo_id)
    repo = SkillRepo.find_by(id: skill_repo_id)
    return unless repo

    SkillRepoSyncer.new(repo).call
  end
end
