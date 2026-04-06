class InvitesController < ApplicationController
  skip_before_action :require_initial_setup
  skip_before_action :require_authentication
  skip_before_action :require_setup

  layout "auth"

  before_action :find_user_by_token

  def show; end

  def update
    if @user.accept_invite(password: invite_params[:password], password_confirmation: invite_params[:password_confirmation])
      reset_session
      session[:user_id] = @user.id
      redirect_to root_path, notice: "Account set up. Welcome to Seneschal."
    else
      @user.invite_token = params[:token]
      render :show, status: :unprocessable_content
    end
  end

  private

  def find_user_by_token
    @user = User.find_by(invite_token: params[:token])
    return if @user

    redirect_to login_path, alert: "Invalid or expired invite link."
  end

  def invite_params
    params.expect(user: [:password, :password_confirmation])
  end
end
