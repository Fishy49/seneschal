class SyncRepoJob < ApplicationJob
  queue_as :default

  def perform(project)
    system("git", "-C", project.local_path, "pull", "--ff-only")
  end
end
