class RegistrationsController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :require_setup

  layout "auth"

  before_action :require_no_users

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    @user.admin = true

    if @user.save
      reset_session
      session[:user_id] = @user.id
      redirect_to root_path, notice: "Admin account created. Welcome to Seneschal."
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def registration_params
    params.expect(user: [:email, :password, :password_confirmation])
  end

  def require_no_users
    return unless User.exists?

    redirect_to root_path
  end
end
