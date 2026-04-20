class AssistantMessagesController < ApplicationController
  before_action :set_conversation

  def create
    content = params[:payload_value].presence || params[:content].to_s.strip
    return head :unprocessable_content if content.blank?

    @conversation.update!(last_page_path: params[:current_page_path].presence)
    @conversation.update!(turbo_token: SecureRandom.hex(32))

    @message = @conversation.assistant_messages.create!(role: "user", content: content)
    @conversation.update!(status: "thinking")

    RunAssistantTurnJob.perform_later(@conversation.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path }
    end
  end

  private

  def set_conversation
    @conversation = current_user.assistant_conversations.recent.first ||
                    current_user.assistant_conversations.create!(status: "idle", turbo_token: SecureRandom.hex(32))
  end
end
