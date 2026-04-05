class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.[](key)
    find_by(key: key)&.value
  end

  def self.[]=(key, value)
    find_or_initialize_by(key: key).update!(value: value.to_s)
  end
end
