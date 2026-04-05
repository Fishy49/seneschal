require "open3"

class CloneRepoJob < ApplicationJob
  queue_as :default

  def perform(project)
    update_status(project, "cloning")

    if File.exist?(File.join(project.local_path, ".git"))
      system("git", "-C", project.local_path, "pull", "--ff-only")
      update_status(project, "ready")
      return
    end

    # Remove empty dir created by path validation so git clone can create it
    FileUtils.rm_rf(project.local_path) if Dir.empty?(project.local_path)

    _, stderr, status = Open3.capture3("git", "clone", project.repo_url, project.local_path)

    if status.success?
      update_status(project, "ready")
    else
      update_status(project, "error")
      Rails.logger.error("Clone failed for #{project.name}: #{stderr}")
    end
  rescue => e
    update_status(project, "error")
    Rails.logger.error("Clone failed for #{project.name}: #{e.message}")
  end

  private

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
