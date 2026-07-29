class User < ApplicationRecord
  # Appearance is personal; brass and status colors are not, so only these
  # three knobs exist. "system" theme resolves client-side.
  THEMES = ["dark", "light", "system"].freeze
  ACCENTS = ["verdigris", "cobalt", "heather", "claret", "moss"].freeze
  DENSITIES = ["cozy", "compact"].freeze

  has_many :user_credentials, dependent: :destroy

  has_secure_password

  store_accessor :settings, :theme, :accent, :density

  validates :email, presence: true, uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :theme, inclusion: { in: THEMES }, allow_blank: true
  validates :accent, inclusion: { in: ACCENTS }, allow_blank: true
  validates :density, inclusion: { in: DENSITIES }, allow_blank: true

  scope :ordered, -> { order(:email) }

  def generate_invite_token!
    update!(invite_token: SecureRandom.urlsafe_base64(32))
  end

  def invite_pending?
    invite_token.present? && invite_accepted_at.nil?
  end

  def accept_invite(password:, password_confirmation:)
    self.password = password
    self.password_confirmation = password_confirmation

    if password.blank?
      errors.add(:password, :blank)
      return false
    end

    self.invite_token = nil
    self.invite_accepted_at = Time.current
    save
  end

  def otp_provisioning_uri
    ROTP::TOTP.new(otp_secret, issuer: "Seneschal").provisioning_uri(email)
  end

  def verify_otp(code)
    return false if otp_secret.blank?

    ROTP::TOTP.new(otp_secret).verify(code.to_s, drift_behind: 30, drift_ahead: 30)
  end

  def generate_otp_secret!
    update!(otp_secret: ROTP::Base32.random)
  end

  def enable_2fa!
    update!(otp_required_for_login: true)
  end

  def disable_2fa!
    update!(otp_secret: nil, otp_required_for_login: false)
  end
end
