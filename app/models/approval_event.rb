class ApprovalEvent < ApplicationRecord
  belongs_to :run_step
  belongs_to :user, optional: true

  ACTIONS = ["approved", "rejected"].freeze

  validates :action, presence: true, inclusion: { in: ACTIONS }

  scope :recent, -> { order(created_at: :desc) }

  def actor_label = user&.email || "system"
end
