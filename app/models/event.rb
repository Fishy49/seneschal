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

  # The only actions that put rows in people's inboxes. Awaiting-approval is
  # deliberately absent: a run waiting for a seal is live state the Inbox
  # queries directly, not history to mark read.
  FANOUT_ACTIONS = ["run.failed", "comment.created"].freeze

  validates :action, presence: true, inclusion: { in: ACTIONS }

  scope :recent, -> { order(created_at: :desc) }
  scope :run_thread, ->(run) { where(subject: run).where.not(action: THREAD_HIDDEN) }

  has_many :notifications, dependent: :delete_all

  after_create_commit :broadcast_to_run_thread
  after_create_commit :fan_out

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

  # Best-effort like everything else on the feed path: a failed fanout must
  # never break the action being recorded.
  def fan_out
    return unless FANOUT_ACTIONS.include?(action)

    case action
    when "run.failed" then fan_out_failure
    when "comment.created" then fan_out_comment
    end
  rescue StandardError => e
    Rails.logger.error("Event##{id} fanout failed: #{e.class}: #{e.message}")
  end

  def fan_out_failure
    run = subject
    return unless run.is_a?(Run)

    deliver(run.participants - [user].compact, reason: "failed", context: run)
  end

  def fan_out_comment
    comment = subject
    return unless comment.is_a?(Comment)

    context = comment.thread_context
    mentioned = comment.mentioned_users
    audience = (context&.participants || []) - [comment.user]
    # Mentions insert first; the unique index then makes plain replies to the
    # same person no-ops, so mention wins when both apply.
    deliver(mentioned, reason: "mention", context: context)
    deliver(audience - mentioned, reason: "reply", context: context)
  end

  def deliver(recipients, reason:, context:)
    now = Time.current
    rows = recipients.compact.uniq.map do |recipient|
      { user_id: recipient.id, event_id: id, reason: reason,
        context_type: context&.class&.name, context_id: context&.id,
        created_at: now, updated_at: now }
    end
    # rubocop:disable Rails/SkipsModelValidations -- insert_all's on-conflict skip is the dedupe
    Notification.insert_all(rows) if rows.any?
    # rubocop:enable Rails/SkipsModelValidations
  end
end
