class UserCredentialsController < ApplicationController
  skip_before_action :require_setup

  def create
    kind = params.expect(:kind).to_s
    unless UserCredential::KINDS.include?(kind)
      redirect_to account_path, alert: "Unknown connection type."
      return
    end

    credential = current_user.user_credentials.find_or_initialize_by(kind: kind)
    credential.value = params[:value].to_s

    if credential.save
      redirect_to account_path, notice: "#{credential.label} saved."
    else
      redirect_to account_path, alert: credential.errors.full_messages.to_sentence
    end
  end

  def destroy
    credential = current_user.user_credentials.find(params.expect(:id))
    credential.destroy
    redirect_to account_path, notice: "#{credential.label} removed."
  end
end
