class RegistrationsController < ApplicationController
  skip_before_action :require_authentication

  layout "auth"

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      reset_session
      session[:user_id] = @user.id
      redirect_to root_path, notice: "Account created. Welcome to Seneschal."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.expect(user: %i[email password password_confirmation])
  end
end
