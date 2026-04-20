require "test_helper"

class RunAssistantTurnJobTest < ActiveJob::TestCase
  setup do
    @conversation = assistant_conversations(:admin_conversation)
    @conversation.update!(status: "thinking", turbo_token: "test-token-admin-abc123")
    @conversation.assistant_messages.create!(role: "user", content: "Hello")
  end

  test "skips if conversation is not in thinking state" do
    @conversation.update!(status: "idle")
    assert_no_difference "AssistantMessage.count" do
      RunAssistantTurnJob.perform_now(@conversation.id)
    end
  end

  test "creates assistant message on success" do
    stub_orchestrator(output: "I can help with that", events: [], session_id: "sess_new") do
      assert_difference "AssistantMessage.count", 1 do
        RunAssistantTurnJob.perform_now(@conversation.id)
      end
      msg = @conversation.assistant_messages.where(role: "assistant").last
      assert_equal "I can help with that", msg.content
    end
  end

  test "updates claude_session_id on success" do
    stub_orchestrator(output: "done", events: [], session_id: "new_session_id") do
      RunAssistantTurnJob.perform_now(@conversation.id)
      assert_equal "new_session_id", @conversation.reload.claude_session_id
    end
  end

  test "sets status to idle on success" do
    stub_orchestrator(output: "done", events: [], session_id: nil) do
      RunAssistantTurnJob.perform_now(@conversation.id)
      assert_equal "idle", @conversation.reload.status
    end
  end

  test "creates error message and sets status to error on failure" do
    stub_orchestrator(error: "claude not found") do
      assert_difference "AssistantMessage.count", 1 do
        RunAssistantTurnJob.perform_now(@conversation.id)
      end
      msg = @conversation.assistant_messages.where(role: "system").last
      assert_includes msg.content, "error"
      assert_equal "error", @conversation.reload.status
    end
  end

  test "handles missing conversation gracefully" do
    assert_nothing_raised do
      RunAssistantTurnJob.perform_now(99_999_999)
    end
  end

  private

  def stub_orchestrator(output: "", events: [], session_id: nil, error: nil, &)
    result = { output: output, events: events, claude_session_id: session_id }
    result[:error] = error if error

    mock_orchestrator = Object.new
    mock_orchestrator.define_singleton_method(:run) { |_msg, &_blk| result }

    AssistantOrchestrator.stub(:new, ->(_conv) { mock_orchestrator }, &)
  end
end
