class ApprovalEvent < ApplicationRecord
  belongs_to :run_step
  belongs_to :user, optional: true

  ACTIONS = ["approved", "rejected"].freeze

  validates :action, presence: true, inclusion: { in: ACTIONS }

  scope :recent, -> { order(created_at: :desc) }

  after_create_commit :broadcast_to_run_thread

  def actor_label = user&.email || "system"

  def run = run_step&.run

  def approved? = action == "approved"

  private

  # A seal is the loudest moment in a run's story, so it lands in the thread
  # the instant it happens.
  def broadcast_to_run_thread
    return unless run

    broadcast_append_later_to(run, target: "run_discussion",
                                   partial: "approval_events/thread_seal",
                                   locals: { approval_event: self })
  end
end
