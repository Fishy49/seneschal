require "test_helper"

class AssistantConversationTest < ActiveSupport::TestCase
  test "belongs to user" do
    conv = assistant_conversations(:admin_conversation)
    assert_equal users(:admin), conv.user
  end

  test "belongs to project optionally" do
    conv = assistant_conversations(:other_conversation)
    assert_nil conv.project
    assert_equal projects(:seneschal), assistant_conversations(:admin_conversation).project
  end

  test "has many messages ordered by created_at" do
    conv = assistant_conversations(:admin_conversation)
    assert_respond_to conv, :assistant_messages
  end

  test "recent scope orders by updated_at desc" do
    convs = AssistantConversation.recent
    assert convs.to_sql.include?("updated_at")
  end

  test "dom_id_for_panel returns expected string" do
    conv = assistant_conversations(:admin_conversation)
    assert_equal "assistant_conversation_#{conv.id}", conv.dom_id_for_panel
  end

  test "valid with user and idle status" do
    conv = AssistantConversation.new(
      user: users(:admin),
      status: "idle",
      turbo_token: SecureRandom.hex(32)
    )
    assert conv.valid?
  end
end
