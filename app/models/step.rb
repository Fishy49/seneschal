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
