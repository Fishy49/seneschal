class DataController < ApplicationController
  before_action :require_admin

  def index
    @project_count = Project.count
    @workflow_count = Workflow.count
    @skill_count = Skill.count
    @task_count = PipelineTask.count
    @template_count = StepTemplate.count
  end

  def export
    data = DataExporter.new.call
    send_data data.to_json,
              filename: "seneschal-export-#{Date.current}.json",
              type: "application/json"
  end

  def import
    file = params[:file]
    unless file
      redirect_to data_management_path, alert: "Please select a file."
      return
    end

    data = JSON.parse(file.read)
    stats = DataImporter.new(data).call

    parts = stats.filter_map { |k, v| "#{v} #{k}" if v.positive? }
    redirect_to root_path, notice: "Import complete: #{parts.join(", ")}."
  rescue JSON::ParserError
    redirect_to data_management_path, alert: "Invalid JSON file."
  rescue ArgumentError => e
    redirect_to data_management_path, alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to data_management_path, alert: "Import failed: #{e.message}"
  end
end
