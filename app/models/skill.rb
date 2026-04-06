class Skill < ApplicationRecord
  belongs_to :project, optional: true
  has_many :steps, dependent: :nullify
  has_many :step_templates, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :project_id }
  validates :body, presence: true

  scope :shared, -> { where(project_id: nil) }
  scope :for_project, ->(project) { where(project_id: [nil, project.id]) }

  def shared?
    project_id.nil?
  end

  def display_name
    shared? ? name : "#{project.name}/#{name}"
  end
end
