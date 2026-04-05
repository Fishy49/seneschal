class TwoFactorController < ApplicationController
  skip_before_action :require_authentication, only: [:new, :create]
  skip_before_action :require_setup

  layout "auth", only: [:new, :create]

  def new
    return if session[:pending_2fa_user_id]

    redirect_to login_path
  end

  def create
    user = User.find_by(id: session[:pending_2fa_user_id])

    unless user
      redirect_to login_path, alert: "Session expired. Please log in again."
      return
    end

    if user.verify_otp(params[:code])
      session.delete(:pending_2fa_user_id)
      reset_session
      session[:user_id] = user.id
      redirect_to root_path, notice: "Welcome back."
    else
      flash.now[:alert] = "Invalid code. Please try again."
      render :new, status: :unprocessable_content
    end
  end

  # 2FA setup (authenticated user)
  def setup
    current_user.generate_otp_secret! if current_user.otp_secret.blank?
    @qr_svg = generate_qr_svg(current_user.otp_provisioning_uri)
  end

  def confirm
    if current_user.verify_otp(params[:code])
      current_user.enable_2fa!
      redirect_to root_path, notice: "Two-factor authentication enabled."
    else
      @qr_svg = generate_qr_svg(current_user.otp_provisioning_uri)
      flash.now[:alert] = "Invalid code. Please scan the QR code and try again."
      render :setup, status: :unprocessable_content
    end
  end

  def disable
    current_user.disable_2fa!
    redirect_to root_path, notice: "Two-factor authentication disabled."
  end

  private

  def generate_qr_svg(uri)
    qrcode = RQRCode::QRCode.new(uri)
    qrcode.as_svg(
      module_size: 4,
      standalone: true,
      use_path: true,
      color: "currentColor",
      shape_rendering: "crispEdges"
    )
  end
end
