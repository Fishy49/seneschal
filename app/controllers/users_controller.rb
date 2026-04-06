class UsersController < ApplicationController
  before_action :require_admin

  def index
    @users = User.ordered
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.password = SecureRandom.hex(32)
    @user.invite_token = SecureRandom.urlsafe_base64(32)

    if @user.save
      redirect_to users_path, notice: "User created. Share the invite link with them."
    else
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    user = User.find(params[:id])
    if user == current_user
      redirect_to users_path, alert: "You cannot delete your own account."
    else
      user.destroy
      redirect_to users_path, notice: "User deleted."
    end
  end

  def reset_invite
    user = User.find(params[:id])
    user.generate_invite_token!
    redirect_to users_path, notice: "Invite link regenerated for #{user.email}."
  end

  private

  def user_params
    params.expect(user: [:email, :admin])
  end
end
