class Workflow < ApplicationRecord
  belongs_to :project
  belongs_to :created_by, class_name: "User", optional: true
  has_many :steps, -> { order(:position) }, dependent: :destroy
  has_many :runs, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :project_id }

  STATS_SAMPLE = 20
  FINISHED_STATUSES = ["completed", "failed", "stopped"].freeze

  Stats = Struct.new(:run_count, :success_rate, :median_cost, keyword_init: true)

  # Social proof for pickers: how often this workflow has been used, how often
  # it worked, and what it usually costs. Rates and costs come from the last
  # STATS_SAMPLE finished runs so an old bad patch stops dragging the number
  # down forever. Cost lives inside each run step's result payload, so the
  # sampled runs are loaded rather than aggregated in SQL.
  def stats
    finished = runs.where(status: FINISHED_STATUSES)
                   .includes(:run_steps)
                   .order(created_at: :desc, id: :desc)
                   .limit(STATS_SAMPLE)
                   .to_a
    completed = finished.select { |run| run.status == "completed" }

    Stats.new(
      run_count: runs.count,
      success_rate: finished.any? ? completed.size.to_f / finished.size : nil,
      median_cost: median(completed.filter_map { |run| run.usage_stats&.dig(:cost_usd) })
    )
  end

  def duplicate_to(target_project)
    WorkflowCopier.new(self, target_project).call
  end

  # Workflow-level runner override. Reads config["runner"] — nil if the
  # workflow doesn't pin a specific runner, in which case StepExecutor
  # falls through to Setting["default_runner"] and finally to "claude_cli".
  def runner_name
    config["runner"].presence if config.is_a?(Hash)
  end

  private

  def median(values)
    return nil if values.empty?

    sorted = values.sort
    middle = sorted.size / 2
    sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
  end
end
