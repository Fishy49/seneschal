require "test_helper"

class AssistantConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "POST create creates a conversation and responds with turbo stream" do
    assert_difference "AssistantConversation.count", 1 do
      post assistant_conversation_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
  end

  test "POST create with project_id scopes conversation" do
    project = projects(:seneschal)
    assert_difference "AssistantConversation.count", 1 do
      post assistant_conversation_path, params: { project_id: project.id }
    end
    assert_equal project.id, AssistantConversation.last.project_id
  end

  test "GET show renders panel" do
    get assistant_conversation_path
    assert_response :success
  end

  test "DELETE destroy clears conversation history" do
    conv = assistant_conversations(:admin_conversation)
    delete assistant_conversation_path
    assert_redirected_to root_path
    assert_equal "idle", conv.reload.status
    assert_nil conv.reload.claude_session_id
  end

  test "requires authentication" do
    sign_out
    post assistant_conversation_path
    assert_redirected_to login_path
  end
end
