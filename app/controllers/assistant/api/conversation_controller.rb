module Assistant
  module Api
    class ConversationController < BaseController
      def state
        messages = current_conversation.assistant_messages.last(20).map do |m|
          { id: m.id, role: m.role, content: m.content, choices: m.choices_array }
        end
        render json: {
          status: current_conversation.status,
          claude_session_id: current_conversation.claude_session_id,
          messages: messages
        }
      end

      def finish_turn
        current_conversation.update!(status: "idle")
        render json: { ok: true }
      end
    end
  end
end
