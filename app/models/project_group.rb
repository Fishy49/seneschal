class ProjectGroup < ApplicationRecord
  has_many :projects, dependent: :nullify
  has_many :skills, dependent: :nullify

  validates :name, presence: true, uniqueness: true

  scope :ordered, -> { order(:name) }
end
