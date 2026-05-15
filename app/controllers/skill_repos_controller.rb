class SkillReposController < ApplicationController
  before_action :require_admin
  before_action :set_skill_repo, only: [:show, :edit, :update, :destroy, :sync]

  def index
    @skill_repos = SkillRepo.order(:priority, :created_at)
    @skill_counts = Skill.active.where.not(skill_repo_id: nil).group(:skill_repo_id).count
  end

  def show
    @active_skills = @skill_repo.skills.active.order(:name)
    @archived_skills = @skill_repo.skills.archived.order(:name)
  end

  def new
    @skill_repo = SkillRepo.new
  end

  def edit; end

  def create
    @skill_repo = SkillRepo.new(create_params)
    if @skill_repo.save
      SyncSkillRepoJob.perform_later(@skill_repo.id)
      redirect_to @skill_repo, notice: "Repo added. Sync enqueued — refresh in a moment to see its skills."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @skill_repo.update(update_params)
      redirect_to @skill_repo, notice: "Repo updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    Skill.where(skill_repo_id: @skill_repo.id).destroy_all
    @skill_repo.destroy_local_clone!
    @skill_repo.destroy
    redirect_to skill_repos_path, notice: "Repo removed."
  end

  def sync
    SyncSkillRepoJob.perform_later(@skill_repo.id)
    redirect_to @skill_repo, notice: "Sync enqueued."
  end

  private

  def set_skill_repo
    @skill_repo = SkillRepo.find(params[:id])
  end

  # On create the operator supplies the URL; branch + priority default if blank.
  # local_path is auto-derived from the name in SkillRepo's before_validation.
  def create_params
    params.expect(skill_repo: [:name, :repo_url, :branch, :priority, :enabled])
  end

  # On edit we deliberately don't expose repo_url — changing it would orphan
  # the existing clone. Operators can remove + re-add to repoint a repo.
  def update_params
    params.expect(skill_repo: [:name, :branch, :priority, :enabled])
  end
end
