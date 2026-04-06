class ApplicationController < ActionController::Base
  before_action :require_initial_setup
  before_action :require_authentication
  before_action :require_setup

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def require_initial_setup
    return if User.exists?
    return if instance_of?(RegistrationsController)

    redirect_to new_admin_setup_path
  end

  def require_authentication
    return if current_user

    redirect_to login_path, alert: "Please sign in."
  end

  def require_setup
    return if Setting["claude_cli"].present? && Setting["gh_cli"].present?

    redirect_to setup_path
  end

  def require_admin
    return if current_user&.admin?

    redirect_to root_path, alert: "Not authorized."
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end
  helper_method :current_user
end
