module StreamLogHelper
  def stream_log_entries(stream_log)
    return [] unless stream_log.is_a?(Array)

    entries = []

    stream_log.each do |event|
      case event["type"]
      when "system"
        entries << { type: :system, model: event["model"] }
      when "assistant"
        (event.dig("message", "content") || []).each do |block|
          case block["type"]
          when "tool_use"
            entries << { type: :tool_use, tool: block["name"], input: block["input"] || {} }
          when "text"
            entries << { type: :text, text: block["text"] } if block["text"].present?
          end
        end
      when "result"
        entries << {
          type: :result,
          cost: event["total_cost_usd"],
          turns: event["num_turns"],
          duration_ms: event["duration_ms"]
        }
      end
    end

    entries
  end

  def tool_use_label(tool, input)
    case tool
    when "Read"
      short_path(input["file_path"])
    when "Edit"
      short_path(input["file_path"])
    when "Write"
      short_path(input["file_path"])
    when "Bash"
      input["command"].to_s.truncate(100)
    when "Glob"
      input["pattern"].to_s
    when "Grep"
      "#{input["pattern"]}#{" in #{short_path(input["path"])}" if input["path"].present?}"
    when "WebSearch", "WebFetch"
      input["query"].to_s.truncate(80)
    else
      input.to_s.truncate(80)
    end
  end

  TOOL_ICONS = {
    "Read" => "eye", "Edit" => "pencil", "Write" => "file-plus",
    "Bash" => "terminal", "Glob" => "search", "Grep" => "search",
    "Agent" => "cpu", "WebSearch" => "globe", "WebFetch" => "globe"
  }.freeze

  def tool_icon_class(tool)
    TOOL_ICONS[tool] || "zap"
  end

  def stream_log_cost_summary(stream_log)
    return nil unless stream_log.is_a?(Array)

    result = stream_log.find { |e| e["type"] == "result" }
    return nil unless result

    parts = []
    parts << "#{result["num_turns"]} turns" if result["num_turns"]
    parts << "$#{format("%.4f", result["total_cost_usd"])}" if result["total_cost_usd"]
    if result["duration_ms"]
      secs = result["duration_ms"] / 1000.0
      parts << if secs < 60
                 "#{secs.round(1)}s"
               else
                 "#{(secs / 60).floor}m #{(secs % 60).round}s"
               end
    end
    parts.join(", ")
  end

  private

  def short_path(path)
    return "" if path.blank?

    parts = path.to_s.split("/")
    parts.length > 2 ? parts.last(2).join("/") : path
  end
end
