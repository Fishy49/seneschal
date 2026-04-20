module Assistant
  module Api
    class UiController < BaseController
      def navigate
        path = params.require(:path)
        Turbo::StreamsChannel.broadcast_stream_to(
          [current_user, :assistant],
          content: %(<turbo-stream action="assistant_navigate" path="#{CGI.escapeHTML(path)}"></turbo-stream>)
        )
        render json: { ok: true }
      end

      def ask_choices
        prompt = params.require(:prompt)
        choices = params.require(:choices)

        message = current_conversation.assistant_messages.create!(
          role: "assistant",
          content: prompt,
          choices: choices.map { |c| { "label" => c[:label] || c["label"], "value" => c[:value] || c["value"] } }
        )
        current_conversation.update!(status: "waiting_user")

        render json: { message_id: message.id }, status: :created
      end

      def ask_text
        prompt = params.require(:prompt)

        message = current_conversation.assistant_messages.create!(
          role: "assistant",
          content: prompt
        )
        current_conversation.update!(status: "waiting_user")

        render json: { message_id: message.id }, status: :created
      end
    end
  end
end
