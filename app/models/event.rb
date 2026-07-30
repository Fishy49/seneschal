class Event < ApplicationRecord
  belongs_to :user, optional: true
  # Optional so the feed survives its subject being deleted later.
  belongs_to :subject, polymorphic: true, optional: true

  ACTIONS = [
    "task.created",
    "run.started",
    "run.stopped",
    "run.resumed",
    "run.completed",
    "run.failed",
    "run.approved",
    "run.rejected",
    "run.awaiting_approval",
    "run.waiting_for_tokens",
    "workflow.created",
    "workflow.updated",
    "comment.created"
  ].freeze

  # Kept out of the run thread: comment.created duplicates the comment
  # itself, and approve/reject are told better by their ApprovalEvent row
  # (which carries the decision comment). All still feed the Activity page.
  THREAD_HIDDEN = ["comment.created", "run.approved", "run.rejected"].freeze

  validates :action, presence: true, inclusion: { in: ACTIONS }

  scope :recent, -> { order(created_at: :desc) }
  scope :run_thread, ->(run) { where(subject: run).where.not(action: THREAD_HIDDEN) }

  after_create_commit :broadcast_to_run_thread

  # Feed writes are fire-and-forget: recording history must never break the
  # action being recorded.
  def self.record(action, subject:, user: nil, metadata: {})
    create!(action: action, subject: subject, user: user, metadata: metadata)
  rescue StandardError => e
    Rails.logger.error("Event.record(#{action}) failed: #{e.class}: #{e.message}")
    nil
  end

  def actor_label = user&.email || "system"

  private

  # Run-level transitions land live in the run page's thread, the same way
  # comments do. The partial renders with no controller context.
  def broadcast_to_run_thread
    return unless subject_type == "Run" && subject.present?
    return if THREAD_HIDDEN.include?(action)

    broadcast_append_later_to(subject, target: "run_discussion",
                                       partial: "events/thread_event", locals: { event: self })
  end
end
