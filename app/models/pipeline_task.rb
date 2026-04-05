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

  def usage_stats
    all = runs.includes(:run_steps).flat_map { |r| r.run_steps.filter_map(&:usage_stats) }
    return nil if all.empty?

    {
      cost_usd: all.sum { |s| s[:cost_usd] },
      input_tokens: all.sum { |s| s[:input_tokens] },
      output_tokens: all.sum { |s| s[:output_tokens] },
      cache_read_tokens: all.sum { |s| s[:cache_read_tokens] },
      cache_creation_tokens: all.sum { |s| s[:cache_creation_tokens] },
      duration_ms: all.sum { |s| s[:duration_ms] },
      num_turns: all.sum { |s| s[:num_turns] }
    }
  end
end
