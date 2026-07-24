class Run < ApplicationRecord
  belongs_to :workflow
  belongs_to :pipeline_task, optional: true
  belongs_to :started_by, class_name: "User", optional: true
  belongs_to :stopped_by, class_name: "User", optional: true
  has_many :run_steps, dependent: :destroy
  has_many :ad_hoc_steps, -> { order(:position) }, class_name: "Step", dependent: :destroy
  has_one :project, through: :workflow

  STATUSES = ["pending", "running", "awaiting_approval", "waiting_for_tokens", "completed", "failed", "stopped"].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: ["pending", "running", "awaiting_approval", "waiting_for_tokens"]) }
  scope :awaiting_approval, -> { where(status: "awaiting_approval") }
  scope :recent, -> { order(created_at: :desc) }

  def active?
    status.in?(["pending", "running", "awaiting_approval", "waiting_for_tokens"])
  end

  def waiting_for_tokens?
    status == "waiting_for_tokens"
  end

  def awaiting_approval?
    status == "awaiting_approval"
  end

  def awaiting_run_step
    run_steps.find_by(status: "awaiting_approval")
  end

  # Human-readable attribution. Runs from before attribution existed, and runs
  # fired by cron or a branch watcher, fall back to the trigger reason.
  def started_by_label
    started_by&.email || input["trigger_reason"].presence || "system"
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
