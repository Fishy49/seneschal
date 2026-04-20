class AssistantConversation < ApplicationRecord
  belongs_to :user
  belongs_to :project, optional: true
  has_many :assistant_messages, -> { order(:created_at) }, dependent: :destroy

  scope :recent, -> { order(updated_at: :desc) }

  def dom_id_for_panel
    "assistant_conversation_#{id}"
  end
end
