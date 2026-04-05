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
end
