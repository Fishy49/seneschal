class Run < ApplicationRecord
  belongs_to :workflow
  belongs_to :pipeline_task, optional: true
  has_many :run_steps, dependent: :destroy
  has_one :project, through: :workflow

  STATUSES = %w[pending running completed failed stopped].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: %w[pending running]) }
  scope :recent, -> { order(created_at: :desc) }

  def active?
    status.in?(%w[pending running])
  end

  def duration
    return nil unless started_at
    (finished_at || Time.current) - started_at
  end
end
