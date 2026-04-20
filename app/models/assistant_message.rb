class AssistantMessage < ApplicationRecord
  belongs_to :assistant_conversation

  ROLES = %w[user assistant system tool_result].freeze
  validates :role, inclusion: { in: ROLES }

  after_create_commit :broadcast_append

  def choices_array
    Array.wrap(choices)
  end

  private

  def broadcast_append
    Turbo::StreamsChannel.broadcast_append_to(
      [assistant_conversation.user, :assistant],
      target: "#{assistant_conversation.dom_id_for_panel}_messages",
      partial: "assistant_messages/message",
      locals: { message: self }
    )
  end
end
