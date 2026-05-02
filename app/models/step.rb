class Step < ApplicationRecord
  belongs_to :workflow, optional: true
  belongs_to :run, optional: true
  belongs_to :skill, optional: true
  has_many :run_steps, dependent: :destroy

  validates :name, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }, unless: -> { run_id.present? }
  validates :step_type, presence: true, inclusion: { in: ["skill", "script", "command", "ci_check", "context_fetch", "prompt"] }
  validates :max_retries, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :timeout, numericality: { only_integer: true, greater_than: 0 }
  validates :skill, presence: true, if: -> { step_type == "skill" }
  validates :body, presence: true, if: -> { step_type.in?(["script", "command", "prompt"]) }
  validate :workflow_or_run_present

  GLOBAL_VARIABLES = ["task_title", "task_body", "task_kind", "repo_owner", "repo_name", "context_files"].freeze

  def produces
    config["produces"] || []
  end

  def consumes
    config["consumes"] || []
  end

  def context_project_ids
    Array(config["context_projects"]).map(&:to_i).uniq
  end

  # Returns Project records for context_projects that are currently cloned
  # and on disk. Any selected IDs that don't resolve — deleted project,
  # missing local_path, or never cloned — are logged and silently skipped
  # so the step still runs.
  def ready_context_projects
    ids = context_project_ids
    return [] if ids.empty?

    found = Project.where(id: ids).to_a
    ready = found.select { |p| p.repo_ready? && p.local_path_exists? }

    missing = ids - found.map(&:id)
    not_ready = (found - ready).map(&:id)
    Rails.logger.warn("Step #{id} context project ids not found: #{missing.inspect}") if missing.any?
    Rails.logger.warn("Step #{id} context projects not ready: #{not_ready.inspect}") if not_ready.any?

    ready
  end

  def manual_approval?
    !!manual_approval
  end

  def prompt_body(context = {})
    case step_type
    when "skill"  then TemplateRenderer.new(skill.body, context).render if skill
    when "prompt" then TemplateRenderer.new(body, context).render if body.present?
    end
  end

  private

  def workflow_or_run_present
    return if workflow_id.present? || run_id.present?

    errors.add(:base, "Step must belong to a workflow or a run")
  end
end
