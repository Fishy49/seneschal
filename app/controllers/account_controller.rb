class AccountController < ApplicationController
  skip_before_action :require_setup

  def edit; end

  def update
    if current_user.update(account_params)
      redirect_to account_path, notice: "Account updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def account_params
    permitted = params.expect(user: [:email, :password, :password_confirmation]).to_h
    permitted.delete(:password) if permitted[:password].blank?
    permitted.delete(:password_confirmation) if permitted[:password_confirmation].blank?
    permitted
  end
end
