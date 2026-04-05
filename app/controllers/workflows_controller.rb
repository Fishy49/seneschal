class WorkflowsController < ApplicationController
  before_action :set_project
  before_action :set_workflow, only: [:show, :edit, :update, :destroy, :trigger]

  def show
    @steps = @workflow.steps
    @recent_runs = @workflow.runs.recent.limit(10)
  end

  def new
    @workflow = @project.workflows.build
  end

  def edit; end

  def create
    @workflow = @project.workflows.build(workflow_params)
    if @workflow.save
      redirect_to project_workflow_path(@project, @workflow), notice: "Workflow created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @workflow.update(workflow_params)
      redirect_to project_workflow_path(@project, @workflow), notice: "Workflow updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @workflow.destroy
    redirect_to project_path(@project), notice: "Workflow deleted."
  end

  def trigger
    run = @workflow.runs.create!(input: trigger_input_params)
    ExecuteRunJob.perform_later(run)
    redirect_to run_path(run), notice: "Run started."
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_workflow
    @workflow = @project.workflows.find(params[:id])
  end

  def workflow_params
    params.expect(workflow: [:name, :description, :trigger_type, :trigger_config])
  end

  def trigger_input_params
    params.permit(input: {}).fetch(:input, {}).to_h
  end
end
