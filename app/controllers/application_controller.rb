class ApplicationController < ActionController::Base
  before_action :require_authentication
  before_action :require_setup

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def require_authentication
    unless current_user
      redirect_to login_path, alert: "Please sign in."
    end
  end

  def require_setup
    return if Setting["claude_cli"].present? && Setting["gh_cli"].present?
    redirect_to setup_path
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end
  helper_method :current_user
end
