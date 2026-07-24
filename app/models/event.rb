class Event < ApplicationRecord
  belongs_to :user, optional: true
  # Optional so the feed survives its subject being deleted later.
  belongs_to :subject, polymorphic: true, optional: true

  ACTIONS = [
    "task.created",
    "run.started",
    "run.stopped",
    "run.completed",
    "run.failed",
    "run.approved",
    "run.rejected",
    "workflow.created",
    "workflow.updated",
    "comment.created"
  ].freeze

  validates :action, presence: true, inclusion: { in: ACTIONS }

  scope :recent, -> { order(created_at: :desc) }

  # Feed writes are fire-and-forget: recording history must never break the
  # action being recorded.
  def self.record(action, subject:, user: nil, metadata: {})
    create!(action: action, subject: subject, user: user, metadata: metadata)
  rescue StandardError => e
    Rails.logger.error("Event.record(#{action}) failed: #{e.class}: #{e.message}")
    nil
  end

  def actor_label = user&.email || "system"
end
