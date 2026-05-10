class ContextQueryLog < ApplicationRecord
  belongs_to :run_step

  validates :variable, presence: true
  validates :expression, presence: true
  validates :returned_bytes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent_first, -> { order(created_at: :asc) }
end
