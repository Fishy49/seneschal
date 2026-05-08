require "open3"

class GenerateCodeMapJob < ApplicationJob
  queue_as :default

  LANGUAGE_BY_EXT = {
    ".rb" => "ruby", ".js" => "javascript", ".jsx" => "javascript",
    ".ts" => "typescript", ".tsx" => "typescript", ".py" => "python",
    ".go" => "go", ".rs" => "rust", ".java" => "java", ".kt" => "kotlin",
    ".swift" => "swift", ".md" => "markdown", ".json" => "json",
    ".yml" => "yaml", ".yaml" => "yaml", ".html" => "html", ".erb" => "html",
    ".css" => "css", ".scss" => "css", ".sh" => "shell", ".sql" => "sql"
  }.freeze

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

    file_paths = result[:tree].filter_map { |f| f[:path] || f["path"] }
    analysis = generate_analysis(file_paths)
    analysis = enforce_tree_consistency(analysis, file_paths)

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

  def generate_analysis(file_paths)
    return { "modules" => [], "file_index" => {} } if file_paths.empty?

    paths_block = file_paths.map { |p| "- #{p}" }.join("\n")

    prompt = <<~PROMPT
      Produce a JSON code map for the repository described below.

      The repository contains EXACTLY these #{file_paths.size} file(s) — no more, no less:
      #{paths_block}

      Return ONLY valid JSON (no markdown fences) with this structure:
      {
        "modules": [
          {
            "name": "Module Name",
            "description": "One-sentence description of what this module does",
            "files": ["path/to/file.rb"]
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

      Hard constraints:
      - Every key in `file_index` MUST be one of the paths listed above. Do not invent paths.
      - Every entry in any `modules[].files` array MUST be one of the paths listed above.
      - Every listed path MUST appear in `file_index` exactly once.
      - If you cannot describe a file, give it an empty summary rather than skipping it.

      Style:
      - Module names should be descriptive domain concepts (e.g., "Authentication", "Game Loop"), not directory names.
      - Keep summaries concise — one sentence each.
      - Infer the language from file extensions.
      - Aim for 1-#{file_paths.size.clamp(3, 15)} modules; very small repos may have just one.
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

  # Filters Claude's response to the canonical file list from FileTreeWalker.
  # Hallucinated paths are dropped (with a warning); files Claude omitted are
  # backfilled with bare entries so every real file is selectable.
  def enforce_tree_consistency(analysis, file_paths)
    allowed = file_paths.to_set
    modules = Array(analysis["modules"]).filter_map do |m|
      next unless m.is_a?(Hash)

      files = Array(m["files"]).select { |f| allowed.include?(f) }
      m.merge("files" => files)
    end

    raw_index = analysis["file_index"].is_a?(Hash) ? analysis["file_index"] : {}
    hallucinated = raw_index.keys - file_paths
    if hallucinated.any?
      sample = hallucinated.first(5).inspect
      ellipsis = hallucinated.size > 5 ? "..." : ""
      Rails.logger.warn("Code map: dropping #{hallucinated.size} hallucinated paths: #{sample}#{ellipsis}")
    end

    file_index = raw_index.slice(*file_paths)

    missing = file_paths - file_index.keys
    if missing.any?
      bucket_name = modules.first&.dig("name") || "Uncategorized"
      missing.each do |path|
        file_index[path] = {
          "summary" => "",
          "module" => bucket_name,
          "language" => infer_language(path)
        }
      end
      bucket = modules.find { |m| m["name"] == bucket_name }
      if bucket
        bucket["files"] = (Array(bucket["files"]) + missing).uniq
      else
        modules << { "name" => bucket_name, "description" => "Files not categorized by analysis.", "files" => missing }
      end
    end

    modules.reject! { |m| Array(m["files"]).empty? }

    { "modules" => modules, "file_index" => file_index }
  end

  def infer_language(path)
    LANGUAGE_BY_EXT[File.extname(path).downcase] || ""
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
