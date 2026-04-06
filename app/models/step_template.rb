class StepTemplate < ApplicationRecord
  belongs_to :skill, optional: true

  validates :name, presence: true, uniqueness: true
  validates :step_type, presence: true, inclusion: { in: ["skill", "script", "command", "ci_check"] }
  validates :skill, presence: true, if: -> { step_type == "skill" }
  validates :body, presence: true, if: -> { step_type.in?(["script", "command"]) }

  scope :ordered, -> { order(:name) }

  def template_data
    {
      step_type: step_type,
      body: body,
      config: config,
      skill_id: skill_id,
      skill_name: skill&.display_name,
      max_retries: max_retries,
      timeout: timeout,
      input_context: input_context,
      injectable_only: injectable_only
    }
  end
end
