class WorkflowImportsController < ApplicationController
  before_action :set_project

  def new
    @existing_workflows = @project.workflows.order(:name)
  end

  def create
    file = params[:file]
    return redirect_to(new_project_workflow_import_path(@project), alert: "Please select a file.") unless file

    data = JSON.parse(file.read)
    result = WorkflowImporter.new(data, **importer_options).call

    redirect_to project_workflow_path(@project, result.workflow), notice: success_notice(result)
  rescue JSON::ParserError
    redirect_to new_project_workflow_import_path(@project), alert: "Invalid JSON file."
  rescue ArgumentError => e
    redirect_to new_project_workflow_import_path(@project), alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to new_project_workflow_import_path(@project), alert: "Import failed: #{e.message}"
  end

  private

  def set_project
    @project = Project.find(params.expect(:project_id))
  end

  def importer_options
    mode = params[:mode] == "replace" ? :replace : :new
    opts = { target_project: @project, mode: mode, name_override: params[:name_override] }
    opts[:replace_workflow] = @project.workflows.find(params.expect(:replace_workflow_id)) if mode == :replace
    opts
  end

  def success_notice(result)
    parts = []
    parts << (result.mode == :replace ? "Workflow replaced." : "Workflow imported.")
    parts << "Created #{pluralize_count(result.created_skills.size, "skill")}." if result.created_skills.any?
    parts << "Created #{pluralize_count(result.created_schemas.size, "JSON schema")}." if result.created_schemas.any?
    parts << "Steps referencing missing skills: #{result.missing_skills.uniq.join(", ")}." if result.missing_skills.any?
    parts.join(" ")
  end

  def pluralize_count(count, singular)
    "#{count} #{count == 1 ? singular : singular.pluralize}"
  end
end
