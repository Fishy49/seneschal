class Skill < ApplicationRecord
  belongs_to :project, optional: true
  belongs_to :project_group, optional: true
  has_many :steps, dependent: :nullify
  has_many :step_templates, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: [:project_id, :project_group_id] }
  validates :body, presence: true
  validate :scope_is_exclusive

  scope :shared, -> { where(project_id: nil, project_group_id: nil) }
  scope :group_scoped, -> { where.not(project_group_id: nil) }
  scope :for_group, ->(group) { where(project_group_id: group.id) }
  scope :for_project, ->(project) {
    base = where(project_id: nil, project_group_id: nil).or(where(project_id: project.id))
    if project.project_group_id.present?
      base.or(where(project_group_id: project.project_group_id))
    else
      base
    end
  }

  def shared?
    project_id.nil? && project_group_id.nil?
  end

  def group_scoped?
    project_group_id.present?
  end

  def project_scoped?
    project_id.present?
  end

  def display_name
    if shared?
      name
    elsif group_scoped?
      "#{project_group.name}/#{name}"
    else
      "#{project.name}/#{name}"
    end
  end

  def scope_value
    if group_scoped?
      "group:#{project_group_id}"
    elsif project_scoped?
      "project:#{project_id}"
    else
      ""
    end
  end

  private

  def scope_is_exclusive
    if project_id.present? && project_group_id.present?
      errors.add(:base, "Skill cannot belong to both a project and a project group")
    end
  end
end
