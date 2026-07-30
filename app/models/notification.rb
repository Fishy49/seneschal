# One row per person per event they should hear about. The Inbox reads
# unread rows; visiting the thing (run or task) marks its rows read, so the
# badge only ever counts what genuinely has not been seen.
class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :event
  # The run or task the event belongs to, denormalized so "mark everything
  # about this run read" is one indexed update.
  belongs_to :context, polymorphic: true, optional: true

  REASONS = ["mention", "reply", "failed"].freeze

  validates :reason, inclusion: { in: REASONS }

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def self.mark_read(user, context)
    # rubocop:disable Rails/SkipsModelValidations -- bulk read-marking has no user input to validate
    unread.where(user: user, context: context).update_all(read_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def read? = read_at.present?
end
