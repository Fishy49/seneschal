require "test_helper"

class AssistantMessageTest < ActiveSupport::TestCase
  test "validates role inclusion" do
    msg = AssistantMessage.new(
      assistant_conversation: assistant_conversations(:admin_conversation),
      role: "invalid",
      content: "test"
    )
    assert_not msg.valid?
    assert_includes msg.errors[:role], "is not included in the list"
  end

  test "accepts valid roles" do
    ["user", "assistant", "system", "tool_result"].each do |role|
      msg = AssistantMessage.new(
        assistant_conversation: assistant_conversations(:admin_conversation),
        role: role,
        content: "test"
      )
      assert msg.valid?, "Expected role #{role} to be valid"
    end
  end

  test "choices_array wraps choices in array" do
    msg = assistant_messages(:assistant_message_with_choices)
    choices = msg.choices_array
    assert_kind_of Array, choices
    assert choices.any?
    assert_equal "Manual trigger", choices.first["label"]
  end

  test "choices_array returns empty array for nil choices" do
    msg = AssistantMessage.new(
      assistant_conversation: assistant_conversations(:admin_conversation),
      role: "assistant",
      content: "hi",
      choices: nil
    )
    assert_equal [], msg.choices_array
  end

  test "belongs to assistant_conversation" do
    msg = assistant_messages(:user_message)
    assert_equal assistant_conversations(:admin_conversation), msg.assistant_conversation
  end
end
