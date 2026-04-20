require "test_helper"

class AssistantMessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
    @conversation = assistant_conversations(:admin_conversation)
  end

  test "POST create with content creates user message" do
    assert_difference "AssistantMessage.count", 1 do
      post assistant_conversation_assistant_messages_path,
           params: { content: "Hello assistant" }
    end
    msg = AssistantMessage.last
    assert_equal "user", msg.role
    assert_equal "Hello assistant", msg.content
  end

  test "POST create with payload_value uses it as content" do
    post assistant_conversation_assistant_messages_path,
         params: { payload_value: "manual", content: "ignored" }
    msg = AssistantMessage.last
    assert_equal "manual", msg.content
  end

  test "POST create enqueues RunAssistantTurnJob" do
    assert_enqueued_with(job: RunAssistantTurnJob) do
      post assistant_conversation_assistant_messages_path,
           params: { content: "Do something" }
    end
  end

  test "POST create sets conversation status to thinking" do
    post assistant_conversation_assistant_messages_path,
         params: { content: "Hello" }
    assert_equal "thinking", @conversation.reload.status
  end

  test "POST create stores current_page_path" do
    post assistant_conversation_assistant_messages_path,
         params: { content: "Hello", current_page_path: "/projects/1" }
    assert_equal "/projects/1", @conversation.reload.last_page_path
  end

  test "POST create with blank content returns unprocessable" do
    assert_no_difference "AssistantMessage.count" do
      post assistant_conversation_assistant_messages_path,
           params: { content: "   " }
    end
    assert_response :unprocessable_content
  end

  test "POST create rotates turbo_token" do
    old_token = @conversation.turbo_token
    post assistant_conversation_assistant_messages_path,
         params: { content: "Hello" }
    assert_not_equal old_token, @conversation.reload.turbo_token
  end
end
