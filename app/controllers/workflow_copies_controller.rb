class WorkflowCopiesController < ApplicationController
  before_action :set_source

  def new
    @target_projects = Project.where.not(id: @source_project.id).order(:name)
  end

  def create
    target = Project.find(params[:target_project_id])
    result = WorkflowCopier.new(@source_workflow, target).call

    notice = "Workflow copied to #{target.name}."
    if result.missing_skills.any?
      notice += " Note: the following project-scoped skills are not present in #{target.name} and will reference the original project's skill until you create local replacements: #{result.missing_skills.join(', ')}."
    end

    redirect_to project_workflow_path(target, result.workflow), notice: notice
  end

  private

  def set_source
    @source_project = Project.find(params[:project_id])
    @source_workflow = @source_project.workflows.find(params[:workflow_id])
  end
end
