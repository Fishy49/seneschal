class Workflow < ApplicationRecord
  belongs_to :project
  has_many :steps, -> { order(:position) }, dependent: :destroy
  has_many :runs, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :project_id }
  validates :trigger_type, presence: true, inclusion: { in: ["manual", "cron", "file_watch"] }

  def duplicate_to(target_project)
    WorkflowCopier.new(self, target_project).call
  end

  # Workflow-level runner override. Reads config["runner"] — nil if the
  # workflow doesn't pin a specific runner, in which case StepExecutor
  # falls through to Setting["default_runner"] and finally to "claude_cli".
  def runner_name
    config["runner"].presence if config.is_a?(Hash)
  end
end
