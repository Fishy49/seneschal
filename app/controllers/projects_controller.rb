class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :edit, :update, :destroy, :clone]

  def index
    @projects = Project.order(:name)
  end

  def show
    @workflows = @project.workflows.order(:name)
    @tasks = @project.pipeline_tasks.recent.limit(10)
    @recent_runs = @project.runs.includes(:workflow).recent.limit(10)
  end

  def new
    @project = Project.new
  end

  def edit; end

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
      redirect_to @project, notice: "Project updated."
    else
      render :edit, status: :unprocessable_content
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

  def repo_status
    render partial: "repo_status", locals: { project: @project }
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.expect(project: [:name, :repo_url, :local_path, :description])
  end
end
