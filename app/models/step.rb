class Step < ApplicationRecord
  belongs_to :workflow
  belongs_to :skill, optional: true
  has_many :run_steps, dependent: :destroy

  validates :name, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :step_type, presence: true, inclusion: { in: ["skill", "script", "command", "ci_check"] }
  validates :max_retries, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :timeout, numericality: { only_integer: true, greater_than: 0 }
  validates :skill, presence: true, if: -> { step_type == "skill" }
  validates :body, presence: true, if: -> { step_type.in?(["script", "command"]) }

  def prompt_body(context = {})
    return nil unless step_type == "skill" && skill

    TemplateRenderer.new(skill.body, context).render
  end
end
