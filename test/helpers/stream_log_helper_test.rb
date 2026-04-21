require "test_helper"

class StreamLogHelperTest < ActionView::TestCase
  test "stream_log_entries parses system event" do
    log = [{ "type" => "system", "model" => "claude-sonnet-4-20250514" }]
    entries = stream_log_entries(log)
    assert_equal 1, entries.length
    assert_equal :system, entries[0][:type]
    assert_equal "claude-sonnet-4-20250514", entries[0][:model]
  end

  test "stream_log_entries parses tool_use" do
    log = [{
      "type" => "assistant",
      "message" => {
        "content" => [{
          "type" => "tool_use",
          "name" => "Read",
          "input" => { "file_path" => "/app/models/user.rb" }
        }]
      }
    }]
    entries = stream_log_entries(log)
    assert_equal 1, entries.length
    assert_equal :tool_use, entries[0][:type]
    assert_equal "Read", entries[0][:tool]
  end

  test "stream_log_entries parses text" do
    log = [{
      "type" => "assistant",
      "message" => { "content" => [{ "type" => "text", "text" => "Hello world" }] }
    }]
    entries = stream_log_entries(log)
    assert_equal :text, entries[0][:type]
    assert_equal "Hello world", entries[0][:text]
  end

  test "stream_log_entries parses result" do
    log = [{ "type" => "result", "total_cost_usd" => 0.05, "num_turns" => 3, "duration_ms" => 60_000 }]
    entries = stream_log_entries(log)
    assert_equal :result, entries[0][:type]
    assert_equal 0.05, entries[0][:cost]
  end

  test "stream_log_entries returns empty for nil" do
    assert_equal [], stream_log_entries(nil)
  end

  test "stream_log_entries returns empty for non-array" do
    assert_equal [], stream_log_entries("not an array")
  end

  test "tool_use_label for Read" do
    assert_equal "models/user.rb", tool_use_label("Read", { "file_path" => "/app/models/user.rb" })
  end

  test "tool_use_label for Bash" do
    assert_equal "ls -la", tool_use_label("Bash", { "command" => "ls -la" })
  end

  test "tool_use_label for Glob" do
    assert_equal "**/*.rb", tool_use_label("Glob", { "pattern" => "**/*.rb" })
  end

  test "tool_use_label for Grep with path" do
    label = tool_use_label("Grep", { "pattern" => "def index", "path" => "/app/controllers" })
    assert_includes label, "def index"
    assert_includes label, "controllers"
  end

  test "tool_icon_class returns known icon" do
    assert_equal "eye", tool_icon_class("Read")
    assert_equal "terminal", tool_icon_class("Bash")
  end

  test "tool_icon_class defaults to zap" do
    assert_equal "zap", tool_icon_class("UnknownTool")
  end

  test "stream_log_cost_summary formats result" do
    log = [{ "type" => "result", "total_cost_usd" => 0.0523, "num_turns" => 5, "duration_ms" => 90_000 }]
    summary = stream_log_cost_summary(log)
    assert_includes summary, "5 turns"
    assert_includes summary, "$0.0523"
    assert_includes summary, "1m 30s"
  end

  test "stream_log_cost_summary returns nil without result" do
    assert_nil stream_log_cost_summary([{ "type" => "system" }])
  end

  test "stream_log_cost_summary returns nil for nil" do
    assert_nil stream_log_cost_summary(nil)
  end

  test "latest_todo_list returns todos from single TodoWrite event" do
    log = [{
      "type" => "assistant",
      "message" => {
        "content" => [{
          "type" => "tool_use",
          "name" => "TodoWrite",
          "input" => {
            "todos" => [
              { "content" => "A", "activeForm" => "Doing A", "status" => "in_progress" },
              { "content" => "B", "activeForm" => "Doing B", "status" => "pending" }
            ]
          }
        }]
      }
    }]
    result = latest_todo_list(log)
    assert_equal 2, result.length
    assert_equal "in_progress", result[0]["status"]
    assert_equal "A", result[0]["content"]
  end

  test "latest_todo_list returns last TodoWrite when multiple exist" do
    log = [
      build_todo_event([{ "content" => "Old", "status" => "pending" }]),
      build_todo_event([{ "content" => "Task 1", "status" => "completed" },
                        { "content" => "Task 2", "status" => "in_progress" },
                        { "content" => "Task 3", "status" => "pending" }])
    ]
    result = latest_todo_list(log)
    assert_equal ["Task 1", "Task 2", "Task 3"], result.pluck("content")
  end

  def build_todo_event(todos)
    {
      "type" => "assistant",
      "message" => {
        "content" => [{ "type" => "tool_use", "name" => "TodoWrite", "input" => { "todos" => todos } }]
      }
    }
  end

  test "latest_todo_list returns nil when no TodoWrite events" do
    log = [{
      "type" => "assistant",
      "message" => {
        "content" => [{
          "type" => "tool_use",
          "name" => "Read",
          "input" => { "file_path" => "/app/models/user.rb" }
        }]
      }
    }]
    assert_nil latest_todo_list(log)
  end

  test "latest_todo_list returns nil for nil" do
    assert_nil latest_todo_list(nil)
  end

  test "latest_todo_list returns nil for non-array" do
    assert_nil latest_todo_list("not an array")
  end

  test "latest_todo_list returns nil when todos array is empty" do
    log = [{
      "type" => "assistant",
      "message" => {
        "content" => [{
          "type" => "tool_use",
          "name" => "TodoWrite",
          "input" => { "todos" => [] }
        }]
      }
    }]
    assert_nil latest_todo_list(log)
  end

  test "todo_status_icon returns distinct icons per status" do
    completed = todo_status_icon("completed")
    in_progress = todo_status_icon("in_progress")
    pending = todo_status_icon("pending")
    assert completed.present?
    assert in_progress.present?
    assert pending.present?
    assert_not_equal completed, in_progress
    assert_not_equal in_progress, pending
    assert_not_equal completed, pending
  end

  test "todo_status_icon falls back to pending icon for unknown" do
    assert_equal todo_status_icon("pending"), todo_status_icon("bogus")
  end

  test "todo_status_class returns completed styling" do
    css = todo_status_class("completed")
    assert_includes css, "text-success"
    assert_includes css, "line-through"
  end

  test "todo_status_class returns in_progress styling" do
    css = todo_status_class("in_progress")
    assert_includes css, "text-accent"
    assert_includes css, "font-semibold"
  end

  test "todo_status_class returns pending styling" do
    css = todo_status_class("pending")
    assert_includes css, "text-content-muted"
  end

  test "tool_use_label for TodoWrite summarizes todos" do
    input = {
      "todos" => [
        { "status" => "in_progress" },
        { "status" => "pending" },
        { "status" => "completed" }
      ]
    }
    label = tool_use_label("TodoWrite", input)
    assert_includes label, "3 todos"
    assert_includes label, "1 in progress"
    assert_includes label, "1 pending"
    assert_includes label, "1 completed"
  end

  test "tool_use_label for TodoWrite with empty todos falls back" do
    input = { "todos" => [] }
    assert_equal input.to_s.truncate(80), tool_use_label("TodoWrite", input)
  end

  test "tool_icon_class maps TodoWrite" do
    assert_equal "check-square", tool_icon_class("TodoWrite")
  end

  test "run_step view renders todo list from stream_log" do
    run_step = run_steps(:passed_step_with_todos)
    run = runs(:completed_run)
    render partial: "runs/run_step", locals: { run_step: run_step, run: run }
    assert_includes rendered, "todo_list_#{run_step.id}"
    assert_includes rendered, "Review plan"
    assert_includes rendered, "Writing plan"
    assert_not_includes rendered, ">Old<"
    assert_includes rendered, "activity log"
  end

  test "stream_log_entries preserves TodoWrite tool_use entry" do
    stream_log = run_steps(:passed_step_with_todos).stream_log
    entries = stream_log_entries(stream_log)
    todo_entries = entries.select { |e| e[:type] == :tool_use && e[:tool] == "TodoWrite" }
    assert todo_entries.any?
    latest = todo_entries.last
    assert_equal 3, latest[:input]["todos"].size
  end
end
