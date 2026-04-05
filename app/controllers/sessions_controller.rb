class SessionsController < ApplicationController
  skip_before_action :require_authentication

  layout "auth"

  def new; end

  def create
    user = User.find_by(email: params[:email])

    if user&.authenticate(params[:password])
      if user.otp_required_for_login?
        session[:pending_2fa_user_id] = user.id
        redirect_to new_two_factor_path
      else
        start_session(user)
        redirect_to root_path, notice: "Welcome back."
      end
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    session[:user_id] = nil
    session[:pending_2fa_user_id] = nil
    redirect_to login_path, notice: "Signed out."
  end

  private

  def start_session(user)
    reset_session
    session[:user_id] = user.id
  end
end
