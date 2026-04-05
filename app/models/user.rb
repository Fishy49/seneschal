class User < ApplicationRecord
  has_secure_password

  validates :email, presence: true, uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }

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
