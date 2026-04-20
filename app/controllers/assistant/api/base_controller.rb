module Assistant
  module Api
    class BaseController < ActionController::API
      before_action :authenticate_bearer!

      attr_reader :current_conversation

      private

      def authenticate_bearer!
        token = request.headers["Authorization"].to_s.split(" ").last
        @current_conversation = AssistantConversation.find_by(turbo_token: token)

        render json: { error: "Unauthorized" }, status: :unauthorized unless @current_conversation
      end

      def current_user
        @current_user ||= current_conversation&.user
      end
    end
  end
end
