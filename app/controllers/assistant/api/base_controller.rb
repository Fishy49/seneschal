module Assistant
  module Api
    class BaseController < ActionController::API
      before_action :authenticate_bearer!

      attr_reader :current_conversation

      private

      def authenticate_bearer!
        header = request.headers["Authorization"].to_s
        token = header.start_with?("Bearer ") ? header.sub(/\ABearer\s+/, "").strip : nil
        @current_conversation = AssistantConversation.find_by(turbo_token: token) if token.present?

        render json: { error: "Unauthorized" }, status: :unauthorized unless @current_conversation
      end

      def current_user
        @current_user ||= current_conversation&.user
      end
    end
  end
end
