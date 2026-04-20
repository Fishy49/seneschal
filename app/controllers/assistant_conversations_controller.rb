class AssistantConversationsController < ApplicationController
  before_action :set_conversation, only: [:show, :destroy]

  def show; end

  def create
    @conversation = current_user.assistant_conversations.create!(
      project_id: params[:project_id].presence,
      status: "idle"
    )

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path }
    end
  end

  def destroy
    @conversation.assistant_messages.destroy_all
    @conversation.update!(status: "idle", claude_session_id: nil)
    redirect_to root_path, notice: "Assistant history cleared."
  end

  private

  def set_conversation
    @conversation = current_user.assistant_conversations.recent.first ||
                    current_user.assistant_conversations.create!(status: "idle")
  end
end
