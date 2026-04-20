class AssistantConversation < ApplicationRecord
  belongs_to :user
  belongs_to :project, optional: true
  has_many :assistant_messages, -> { order(:created_at) }, dependent: :destroy

  before_validation :ensure_turbo_token
  validates :turbo_token, presence: true, uniqueness: true

  scope :recent, -> { order(updated_at: :desc) }

  def dom_id_for_panel
    "assistant_conversation_#{id}"
  end

  def rotate_turbo_token!
    update!(turbo_token: SecureRandom.hex(32))
  end

  private

  def ensure_turbo_token
    self.turbo_token ||= SecureRandom.hex(32)
  end
end
