require "open3"

class GenerateCodeMapJob < ApplicationJob
  queue_as :default

  def perform(project)
    project.reload
    code_map = project.code_map || project.create_code_map!
    update_status(code_map, "generating")

    walker = FileTreeWalker.new(project)
    result = walker.call

    if result[:tree].empty?
      update_status(code_map, "error", error: "No files found in repository")
      return
    end

    analysis = generate_analysis(result[:tree], project.local_path)

    code_map.update!(
      tree: result[:tree],
      modules: analysis["modules"] || [],
      file_index: analysis["file_index"] || {},
      file_count: result[:file_count],
      commit_sha: walker.commit_sha,
      generated_at: Time.current,
      status: "ready",
      error_message: nil
    )

    code_map.populate_search_index!
    broadcast_status(code_map)
  rescue StandardError => e
    code_map = project.code_map
    update_status(code_map, "error", error: e.message) if code_map
    Rails.logger.error("Code map generation failed for #{project.name}: #{e.message}")
  end

  private

  def generate_analysis(tree, _repo_path)
    file_paths = tree.map { |f| f[:path] || f["path"] }
    grouped = file_paths.group_by { |p| File.dirname(p) }

    tree_text = grouped.sort.map do |dir, files|
      "#{dir}/\n#{files.map { |f| "  #{File.basename(f)}" }.join("\n")}"
    end.join("\n\n")

    prompt = <<~PROMPT
      Analyze this codebase file structure and produce a JSON code map.

      FILE TREE:
      #{tree_text}

      Return ONLY valid JSON (no markdown fences) with this structure:
      {
        "modules": [
          {
            "name": "Module Name",
            "description": "One-sentence description of what this module does",
            "files": ["path/to/file.rb", "path/to/other.rb"]
          }
        ],
        "file_index": {
          "path/to/file.rb": {
            "summary": "One-sentence description of this file",
            "module": "Module Name",
            "language": "ruby"
          }
        }
      }

      Guidelines:
      - Group files into logical modules based on directory structure and naming conventions
      - Every file in the tree must appear in exactly one module and in file_index
      - Module names should be descriptive domain concepts (e.g., "Authentication", "API Controllers"), not directory names
      - Keep summaries concise — one sentence each
      - Infer the language from file extensions
      - Aim for 5-15 modules depending on project size
    PROMPT

    stdout, stderr, status = Open3.capture3(
      "claude", "-p", "--model", "claude-haiku-4-5-20251001",
      stdin_data: prompt
    )

    raise "Claude analysis failed: #{stderr.presence || "unknown error"}" unless status.success?

    raw = stdout.strip.gsub(/\A```\w*\n?/, "").gsub(/\n?```\z/, "").strip
    JSON.parse(raw)
  rescue JSON::ParserError => e
    raise "Failed to parse Claude response: #{e.message}"
  end

  def update_status(code_map, status, error: nil)
    code_map.update!(status: status, error_message: error)
    broadcast_status(code_map)
  end

  def broadcast_status(code_map)
    Turbo::StreamsChannel.broadcast_replace_to(
      code_map.project,
      target: "code_map_status",
      partial: "code_maps/status",
      locals: { code_map: code_map, project: code_map.project }
    )
  end
end
