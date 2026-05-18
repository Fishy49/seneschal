class ProjectGroup < ApplicationRecord
  has_many :projects, dependent: :nullify

  validates :name, presence: true, uniqueness: true

  scope :ordered, -> { order(:name) }
end
