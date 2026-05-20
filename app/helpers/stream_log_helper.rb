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
    when "Read", "Edit", "Write"  then short_path(input["file_path"])
    when "Bash"                   then input["command"].to_s.truncate(100)
    when "Glob"                   then input["pattern"].to_s
    when "Grep"                   then grep_label(input)
    when "WebSearch", "WebFetch"  then input["query"].to_s.truncate(80)
    when "TodoWrite"              then todo_write_label(input)
    when "TaskCreate"             then input["subject"].to_s.presence&.truncate(80) || input.to_s.truncate(80)
    when "TaskUpdate"             then task_update_label(input)
    else input.to_s.truncate(80)
    end
  end

  TOOL_ICONS = {
    "Read" => "eye", "Edit" => "pencil", "Write" => "file-plus",
    "Bash" => "terminal", "Glob" => "search", "Grep" => "search",
    "Agent" => "cpu", "WebSearch" => "globe", "WebFetch" => "globe",
    "TodoWrite" => "check-square",
    # The SDK-bundled `claude` CLI exposes the task tools instead of TodoWrite
    # (TaskCreate adds one entry, TaskUpdate mutates by taskId). They serve the
    # same "running todo list" role from the operator's perspective, so we
    # group them under the same icon family.
    "TaskCreate" => "check-square", "TaskUpdate" => "check-square"
  }.freeze

  TODO_STATUS_ICONS = { "completed" => "✓", "in_progress" => "▸", "pending" => "○" }.freeze
  TODO_STATUS_CLASSES = {
    "completed" => "text-success line-through", "in_progress" => "text-accent font-semibold",
    "pending" => "text-content-muted"
  }.freeze

  # Reconstruct the running todo list from a stream_log, supporting both event
  # styles the harness can emit:
  #
  # - TodoWrite (Claude CLI runner): each call carries the FULL list under
  #   `input.todos`. We treat each TodoWrite as a snapshot that replaces the
  #   list.
  # - TaskCreate / TaskUpdate (SDK runner — its bundled CLI exposes the task
  #   tools instead): TaskCreate adds one row at a time with `subject` /
  #   `activeForm`, TaskUpdate mutates an existing row's `status` by `taskId`.
  #   The harness assigns sequential ids to tasks (1, 2, 3, …) in the order
  #   they're created, so we mirror that and look up updates by index.
  #
  # Returns a TodoWrite-shaped array (`{"content":, "status":, "activeForm":}`)
  # so the existing `_todo_list` partial doesn't need to know which tool
  # family produced the data.
  def latest_todo_list(stream_log)
    return nil unless stream_log.is_a?(Array)

    state = { todos: [], tasks_by_id: {}, next_task_id: 1 }
    stream_log.each { |event| apply_todo_events(event, state) }
    state[:todos].any? ? state[:todos] : nil
  end

  def todo_status_icon(status) = TODO_STATUS_ICONS[status] || TODO_STATUS_ICONS["pending"]
  def todo_status_class(status) = TODO_STATUS_CLASSES[status] || TODO_STATUS_CLASSES["pending"]
  def tool_icon_class(tool) = TOOL_ICONS[tool] || "zap"

  # A richer view of stream_log for the trajectory replay + diff surfaces.
  # Differs from `stream_log_entries` in three ways:
  #   - preserves `thinking` blocks (the live ticker hides them; replay wants
  #     them as a collapsible drill-down)
  #   - pairs `tool_use` blocks with their matching `tool_result` from the
  #     follow-up user message, so the timeline can render the call + its
  #     outcome as one collapsible card
  #   - tags every entry with the raw `event_idx` it came from so the diff
  #     view can align by stream-log position
  def stream_log_trajectory(stream_log)
    return [] unless stream_log.is_a?(Array)

    pending_tool_uses = {}
    entries = []

    stream_log.each_with_index do |event, idx|
      append_trajectory_event(event, idx, entries, pending_tool_uses)
    end

    entries
  end

  # Stable signature of a trajectory entry, ignoring volatile fields (cost,
  # timing, tool_use_id) so two runs that did "the same thing" produce
  # matching signatures. Used by the diff view to align rows.
  def trajectory_signature(entry)
    case entry[:kind]
    when :tool_use
      input = entry[:input].is_a?(Hash) ? entry[:input].sort.to_h.to_s.truncate(120) : entry[:input].to_s.truncate(120)
      "tool_use:#{entry[:tool]}:#{input}"
    when :text
      "text:#{entry[:text].to_s.strip.truncate(80)}"
    when :thinking
      "thinking" # ignore the body — too noisy to compare verbatim
    when :tool_result
      "tool_result:#{entry[:is_error] ? "error" : "ok"}"
    when :result
      "result:#{entry[:stop_reason]}"
    when :system
      "system:#{entry[:model]}"
    when :error
      "error"
    else
      entry[:kind].to_s
    end
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

  def grep_label(input)
    "#{input["pattern"]}#{" in #{short_path(input["path"])}" if input["path"].present?}"
  end

  def todo_write_label(input)
    todos = input["todos"]
    return input.to_s.truncate(80) unless todos.is_a?(Array) && todos.any?

    c = todos.group_by { |t| t["status"].to_s }.transform_values(&:size)
    "#{todos.size} todos (#{c["in_progress"].to_i} in progress, " \
      "#{c["pending"].to_i} pending, #{c["completed"].to_i} completed)"
  end

  def task_update_label(input)
    id = input["taskId"].to_s.presence
    status = input["status"].to_s.presence
    id && status ? "##{id} → #{status}" : input.to_s.truncate(80)
  end

  # `state` is a mutable hash carrying { todos:, tasks_by_id:, next_task_id: }
  # so the per-event helpers can append, mutate by id, or snapshot-replace
  # without threading three return values back through each call.
  def apply_todo_events(event, state)
    return unless event["type"] == "assistant"

    (event.dig("message", "content") || []).each do |block|
      next unless block["type"] == "tool_use"

      case block["name"]
      when "TodoWrite"  then apply_todo_write_snapshot(block, state)
      when "TaskCreate" then apply_task_create(block, state)
      when "TaskUpdate" then apply_task_update(block, state)
      end
    end
  end

  def apply_todo_write_snapshot(block, state)
    snapshot = block.dig("input", "todos")
    return unless snapshot.is_a?(Array) && snapshot.any?

    state[:todos] = snapshot.map { |t| t.is_a?(Hash) ? t.dup : t }
    state[:tasks_by_id].clear # TodoWrite owns the whole list; drop any Task* state
  end

  def apply_task_create(block, state)
    subject = block.dig("input", "subject").to_s
    return if subject.empty?

    entry = {
      "content" => subject,
      "activeForm" => block.dig("input", "activeForm").to_s.presence || subject,
      "status" => "pending"
    }
    state[:todos] << entry
    state[:tasks_by_id][state[:next_task_id].to_s] = entry
    state[:next_task_id] += 1
  end

  def apply_task_update(block, state)
    id = block.dig("input", "taskId").to_s
    status = block.dig("input", "status").to_s
    return if id.empty? || status.empty?

    entry = state[:tasks_by_id][id]
    entry["status"] = status if entry
  end

  def append_trajectory_event(event, idx, entries, pending_tool_uses)
    case event["type"]
    when "system"
      entries << { event_idx: idx, kind: :system, model: event["model"] }
    when "assistant"
      assistant_blocks(event).each { |block| append_assistant_block(block, idx, entries, pending_tool_uses) }
    when "user"
      assistant_blocks(event).each { |block| append_tool_result_block(block, idx, entries, pending_tool_uses) }
    when "result"
      entries << {
        event_idx: idx, kind: :result, cost: event["total_cost_usd"],
        turns: event["num_turns"], duration_ms: event["duration_ms"],
        stop_reason: event["stop_reason"]
      }
    when "error"
      entries << { event_idx: idx, kind: :error, message: event["message"].to_s }
    end
  end

  def assistant_blocks(event)
    event.dig("message", "content") || []
  end

  def append_assistant_block(block, idx, entries, pending_tool_uses)
    case block["type"]
    when "thinking"
      text = block["thinking"].to_s
      entries << { event_idx: idx, kind: :thinking, text: text } if text.present?
    when "tool_use"
      entry = {
        event_idx: idx, kind: :tool_use, tool: block["name"],
        input: block["input"] || {}, tool_use_id: block["id"], result: nil
      }
      entries << entry
      pending_tool_uses[block["id"]] = entry if block["id"]
    when "text"
      entries << { event_idx: idx, kind: :text, text: block["text"] } if block["text"].present?
    end
  end

  def append_tool_result_block(block, idx, entries, pending_tool_uses)
    return unless block["type"] == "tool_result"

    pending = pending_tool_uses.delete(block["tool_use_id"])
    payload = { content: block["content"], is_error: block["is_error"] ? true : false }
    if pending
      pending[:result] = payload
    else
      entries << { event_idx: idx, kind: :tool_result, tool_use_id: block["tool_use_id"], **payload }
    end
  end

  def short_path(path)
    return "" if path.blank?

    parts = path.to_s.split("/")
    parts.length > 2 ? parts.last(2).join("/") : path
  end
end
