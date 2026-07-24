# A tokenized, no-login, heavily redacted view of a single run, for people who
# do not have a Seneschal account.
class ShareLink < ApplicationRecord
  belongs_to :run
  belongs_to :created_by, class_name: "User", optional: true

  DEFAULT_LIFETIME = 30.days

  validates :token, presence: true, uniqueness: true

  before_validation :assign_defaults, on: :create

  scope :active, -> { where(expires_at: Time.current..) }
  scope :recent, -> { order(created_at: :desc) }

  def expired? = expires_at.past?

  private

  def assign_defaults
    self.token ||= SecureRandom.urlsafe_base64(32)
    self.expires_at ||= DEFAULT_LIFETIME.from_now
  end
end
