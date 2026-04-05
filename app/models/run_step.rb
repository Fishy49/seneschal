class RunStep < ApplicationRecord
  belongs_to :run
  belongs_to :step

  STATUSES = %w[pending queued running passed failed retrying skipped].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :attempt, numericality: { only_integer: true, greater_than: 0 }
end
