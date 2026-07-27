class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :edit, :update, :destroy, :clone, :refetch]

  SECTIONS = ["overview", "workflows", "tasks", "runs", "skills", "settings"].freeze
  RUNS_LIMIT = 50

  def index
    @project_groups = ProjectGroup.ordered
    @projects = Project.includes(:project_group).order(:name)
    @projects = @projects.in_group(params[:group_id]) if params[:group_id].present?
    @projects.each(&:refresh_repo_status!)
  end

  def show
    @project.refresh_repo_status!
    load_section
  end

  def new
    @project = Project.new
  end

  # The project form lives on the hub's Settings tab; this route stays valid
  # for old links and for the Edit Path affordance on a failed clone.
  def edit
    redirect_to project_path(@project, section: "settings")
  end

  def create
    @project = Project.new(project_params)
    if @project.save
      redirect_to @project, notice: "Project created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @project.update(project_params)
      redirect_to project_path(@project, section: "settings"), notice: "Project updated."
    else
      @section = "settings"
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    @project.destroy
    redirect_to projects_path, notice: "Project deleted."
  end

  def clone
    @project.update!(repo_status: "cloning")
    CloneRepoJob.perform_later(@project)
    redirect_to @project, notice: "Repository cloning started..."
  end

  def refetch
    unless @project.repo_ready?
      redirect_to @project, alert: "Clone the repository before refetching."
      return
    end

    @project.update!(repo_status: "refetching")
    RefetchRepoJob.perform_later(@project)
    redirect_to @project, notice: "Refetching latest from origin..."
  end

  def repo_status
    render partial: "repo_status", locals: { project: @project }
  end

  def import_skills
    result = SkillImporter.new(@project).call

    if result.nil?
      redirect_to @project, alert: "No .claude/skills directory found in this repository."
    elsif result[:imported].any?
      redirect_to @project, notice: "Imported #{result[:imported].size} skill(s): #{result[:imported].join(", ")}."
    else
      redirect_to @project, notice: "No new skills to import (#{result[:skipped].size} already exist)."
    end
  end

  private

  def set_project
    @project = Project.find(params.expect(:id))
  end

  # Only the requested tab's data is loaded; the sidebar links straight at the
  # default tab, so it has to stay cheap.
  def load_section
    @section = SECTIONS.include?(params[:section]) ? params[:section] : "overview"

    case @section
    when "overview"
      @recent_runs = project_runs.limit(5)
    when "workflows"
      @workflows = @project.workflows.includes(:steps, :runs).order(:name)
      @last_runs = @workflows.to_h { |workflow| [workflow.id, workflow.runs.max_by(&:created_at)] }
      @stats = @workflows.to_h { |workflow| [workflow.id, workflow.stats] }
      @access = @workflows.to_h { |workflow| [workflow.id, WorkflowAccessSummary.for(workflow)] }
    when "tasks"
      @tasks = @project.pipeline_tasks.includes(:workflow).recent
      @tasks = @tasks.where(status: params[:status]) if PipelineTask::STATUSES.include?(params[:status])
    when "runs"
      @runs = project_runs.limit(RUNS_LIMIT)
    when "skills"
      @skills = @project.skills.order(:name)
      @skill_usage = Step.where(skill_id: @skills.map(&:id)).group(:skill_id).count
    end
  end

  def project_runs
    @project.runs.includes(:pipeline_task, workflow: :project).recent
  end

  def project_params
    params.expect(project: [:name, :repo_url, :local_path, :description, :markdown_context, :project_group_id, :skip_permissions])
  end
end
