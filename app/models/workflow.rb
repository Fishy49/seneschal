class Workflow < ApplicationRecord
  belongs_to :project
  has_many :steps, -> { order(:position) }, dependent: :destroy
  has_many :runs, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :project_id }
  validates :trigger_type, presence: true, inclusion: { in: ["manual", "cron", "file_watch"] }
end
