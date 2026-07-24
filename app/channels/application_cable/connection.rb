module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    # Same encrypted cookie the HTTP side reads through `session[:user_id]`.
    def find_verified_user
      session = cookies.encrypted[Rails.application.config.session_options[:key]]
      user_id = session && (session["user_id"] || session[:user_id])

      User.find_by(id: user_id) || reject_unauthorized_connection
    end
  end
end
