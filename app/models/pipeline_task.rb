class PipelineTask < ApplicationRecord
  belongs_to :project
  belongs_to :workflow, optional: true
  has_many :runs, dependent: :nullify

  KINDS = ["feature", "bugfix", "chore"].freeze
  STATUSES = ["draft", "ready", "running", "completed", "failed"].freeze
  TRIGGER_TYPES = ["manual", "cron", "github_watch"].freeze

  CRON_PRESETS = [
    { label: "Every hour",           cron: "0 * * * *" },
    { label: "Every 4 hours",        cron: "0 */4 * * *" },
    { label: "Daily at 9am",         cron: "0 9 * * *" },
    { label: "Weekdays at 9am",      cron: "0 9 * * 1-5" },
    { label: "Weekly (Monday 9am)",  cron: "0 9 * * 1" }
  ].freeze

  validates :title, presence: true
  validates :body, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :trigger_type, presence: true, inclusion: { in: TRIGGER_TYPES }
  validates :workflow, presence: true, if: -> { status != "draft" }
  validate :validate_trigger_config

  scope :recent, -> { order(updated_at: :desc) }
  scope :actionable, -> { where(status: ["draft", "ready"]) }
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :scheduled_cron, -> { active.where(trigger_type: "cron") }
  scope :branch_watching, -> { active.where(trigger_type: "github_watch") }

  def archived? = archived_at.present?
  def manual? = trigger_type == "manual"
  def cron? = trigger_type == "cron"
  def github_watch? = trigger_type == "github_watch"

  def executable?
    workflow.present? && status.in?(["ready", "failed"])
  end

  def latest_run
    runs.order(created_at: :desc).first
  end

  def cron_expression = trigger_config&.dig("cron")
  def watched_repo_url = trigger_config&.dig("repo_url")
  def watched_branch = trigger_config&.dig("branch")
  def last_seen_sha = trigger_config&.dig("last_seen_sha")

  def last_fired_at
    raw = trigger_config&.dig("last_fired_at")
    raw.present? ? Time.zone.parse(raw) : nil
  end

  def fugit_cron
    return nil if cron_expression.blank?

    Fugit::Cron.parse(cron_expression)
  end

  # Used by the manual Execute button, scheduled cron ticks, and branch-watch
  # polling. All three create a Run through this single code path.
  def enqueue_run!(reason: "manual")
    raise "Task is not executable" if workflow.blank?

    context = {
      "task_title" => title,
      "task_body" => body,
      "task_kind" => kind,
      "trigger_reason" => reason,
      "repo_owner" => project.repo_owner,
      "repo_name" => project.repo_name
    }

    if context_files.present? && context_files.any?
      context["context_files"] = context_files.map do |f|
        f.is_a?(Hash) ? "#{f["path"]}: #{f["reason"]}" : f.to_s
      end.join("\n")
    end

    run = runs.create!(
      workflow: workflow,
      input: {
        "task_id" => id,
        "task_title" => title,
        "task_kind" => kind,
        "trigger_reason" => reason
      },
      context: context
    )
    update!(status: "running") unless status == "running"
    ExecuteRunJob.perform_later(run)
    run
  end

  def record_cron_fire!(fired_at)
    self.trigger_config = (trigger_config || {}).merge("last_fired_at" => fired_at.iso8601)
    save!(validate: false)
  end

  def record_seen_sha!(sha)
    self.trigger_config = (trigger_config || {}).merge("last_seen_sha" => sha)
    save!(validate: false)
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

  private

  def validate_trigger_config
    case trigger_type
    when "cron"
      if cron_expression.blank?
        errors.add(:trigger_config, "must include a cron expression")
      elsif Fugit::Cron.parse(cron_expression).nil?
        errors.add(:trigger_config, "has an invalid cron expression")
      end
    when "github_watch"
      errors.add(:trigger_config, "must include a repo URL") if watched_repo_url.blank?
      errors.add(:trigger_config, "must include a branch") if watched_branch.blank?
    end
  end
end
