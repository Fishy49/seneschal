class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :edit, :update, :destroy, :clone, :refetch]

  SECTIONS = ["overview", "workflows", "tasks", "runs", "skills", "settings"].freeze
  RUNS_LIMIT = 50
  WORKFLOW_SORTS = ["name", "most_run", "recent"].freeze

  def self.workflow_sort(value) = WORKFLOW_SORTS.include?(value) ? value : "name"

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
    @onboarding = params[:onboarding].present?
  end

  # The project form lives on the hub's Settings tab; this route stays valid
  # for old links and for the Edit Path affordance on a failed clone.
  def edit
    redirect_to project_path(@project, section: "settings")
  end

  def create
    @onboarding = params[:onboarding].present?
    attributes = project_params
    attributes[:local_path] = default_local_path(attributes) if @onboarding && attributes[:local_path].blank?
    @project = Project.new(attributes)

    unless @project.save
      render :new, status: :unprocessable_content
      return
    end

    return redirect_to(@project, notice: "Project created.") unless @onboarding

    # On first boot there is nothing to decide about the clone, so just start it.
    @project.update!(repo_status: "cloning")
    CloneRepoJob.perform_later(@project)
    redirect_to project_path(@project, onboarding: 1)
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
      @workflows = sorted_workflows
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

  # Ordering by run activity uses a left join and a count; at self-hosted
  # scale that is cheaper than maintaining a counter column.
  def sorted_workflows
    scope = @project.workflows.includes(:steps, :runs, :created_by)

    case self.class.workflow_sort(params[:sort])
    when "most_run"
      scope.left_joins(:runs).group(:id).order(Arel.sql("COUNT(runs.id) DESC"), :name)
    when "recent"
      scope.left_joins(:runs).group(:id).order(Arel.sql("MAX(runs.created_at) DESC"), :name)
    else
      scope.order(:name)
    end
  end

  # The onboarding form does not ask where to put the checkout; the JS fills it
  # in and this is the backstop when it has not.
  def default_local_path(attributes)
    slug = attributes[:name].to_s.strip.downcase.gsub(/\s+/, "_")
    slug = attributes[:repo_url].to_s[%r{/([^/]+?)(?:\.git)?\z}, 1].to_s if slug.blank?
    return nil if slug.blank?

    Rails.root.join("repos", slug).to_s
  end

  def project_params
    params.expect(project: [:name, :repo_url, :local_path, :description, :markdown_context, :project_group_id, :skip_permissions])
  end
end
