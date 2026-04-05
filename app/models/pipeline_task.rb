class PipelineTask < ApplicationRecord
  belongs_to :project
  belongs_to :workflow, optional: true
  has_many :runs, dependent: :nullify

  KINDS = %w[feature bugfix chore].freeze
  STATUSES = %w[draft ready running completed failed].freeze

  validates :title, presence: true
  validates :body, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :workflow, presence: true, if: -> { status != "draft" }

  scope :recent, -> { order(updated_at: :desc) }
  scope :actionable, -> { where(status: %w[draft ready]) }

  def executable?
    workflow.present? && status.in?(%w[ready failed])
  end

  def latest_run
    runs.order(created_at: :desc).first
  end
end
