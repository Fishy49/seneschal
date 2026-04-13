require "open3"

class CodeMapsController < ApplicationController
  before_action :set_project

  def show
    @code_map = @project.code_map
    redirect_to @project, alert: "No code map yet. Generate one first." unless @code_map
  end

  def generate
    code_map = @project.code_map || @project.create_code_map!
    code_map.update!(status: "generating", error_message: nil)
    GenerateCodeMapJob.perform_later(@project)
    redirect_to @project, notice: "Code map generation started..."
  end

  def status
    @code_map = @project.code_map
    render partial: "code_maps/status", locals: { code_map: @code_map, project: @project }
  end

  def search
    code_map = @project.code_map
    results = code_map&.ready? ? code_map.search(params[:q]) : []
    render json: { results: results }
  end

  def suggestions
    code_map = @project.code_map
    unless code_map&.ready?
      render json: { error: "Code map not ready" }, status: :unprocessable_content
      return
    end

    description = params[:description].to_s.strip
    if description.blank?
      render json: { error: "No description provided" }, status: :unprocessable_content
      return
    end

    modules_summary = code_map.modules.map do |m|
      "- #{m["name"]}: #{m["description"]} (#{m["files"]&.size || 0} files)"
    end.join("\n")

    file_list = code_map.file_index.map do |path, info|
      "- #{path}: #{info["summary"]}"
    end.join("\n")

    prompt = <<~PROMPT
      Given this task description:
      "#{description}"

      And this project code map:

      MODULES:
      #{modules_summary}

      FILES:
      #{file_list}

      Which files are most relevant to this task? Return ONLY valid JSON (no markdown fences):
      {
        "files": [
          { "path": "path/to/file.rb", "reason": "Brief reason why this file is relevant" }
        ]
      }

      Return 5-15 of the most relevant files, ranked by relevance. Only include files that are genuinely useful for the task.
    PROMPT

    stdout, stderr, status = Open3.capture3(
      "claude", "-p", "--model", "claude-haiku-4-5-20251001",
      stdin_data: prompt
    )

    if status.success? && stdout.present?
      raw = stdout.strip.gsub(/\A```\w*\n?/, "").gsub(/\n?```\z/, "").strip
      data = JSON.parse(raw)
      render json: data
    else
      render json: { error: stderr.presence || "Suggestion failed" }, status: :unprocessable_content
    end
  rescue JSON::ParserError
    render json: { error: "Failed to parse suggestions" }, status: :unprocessable_content
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
