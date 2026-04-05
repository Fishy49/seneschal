class Run < ApplicationRecord
  belongs_to :workflow
  belongs_to :pipeline_task, optional: true
  has_many :run_steps, dependent: :destroy
  has_one :project, through: :workflow

  STATUSES = ["pending", "running", "completed", "failed", "stopped"].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: ["pending", "running"]) }
  scope :recent, -> { order(created_at: :desc) }

  def active?
    status.in?(["pending", "running"])
  end

  def duration
    return nil unless started_at

    (finished_at || Time.current) - started_at
  end

  def usage_stats
    all = run_steps.filter_map(&:usage_stats)
    return nil if all.empty?

    aggregate_usage(all)
  end

  private

  def aggregate_usage(stats)
    {
      cost_usd: stats.sum { |s| s[:cost_usd] },
      input_tokens: stats.sum { |s| s[:input_tokens] },
      output_tokens: stats.sum { |s| s[:output_tokens] },
      cache_read_tokens: stats.sum { |s| s[:cache_read_tokens] },
      cache_creation_tokens: stats.sum { |s| s[:cache_creation_tokens] },
      duration_ms: stats.sum { |s| s[:duration_ms] },
      num_turns: stats.sum { |s| s[:num_turns] }
    }
  end
end
