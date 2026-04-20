class RunAssistantTurnJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = AssistantConversation.find(conversation_id)
    return unless conversation.status == "thinking"

    user_message = conversation.assistant_messages.where(role: "user").last
    return unless user_message

    orchestrator = AssistantOrchestrator.new(conversation)

    result = orchestrator.run(user_message.content) do |event|
      broadcast_progress(conversation, event)
    end

    if result[:error].present?
      conversation.assistant_messages.create!(
        role: "system",
        content: "Assistant hit an error, try again. (#{result[:error]})"
      )
      conversation.update!(status: "error")
    else
      conversation.assistant_messages.create!(
        role: "assistant",
        content: result[:output].presence || "(no response)",
        events: (result[:events] || []).last(50)
      )
      conversation.update!(
        status: "idle",
        claude_session_id: result[:claude_session_id]
      )
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  private

  def broadcast_progress(conversation, event)
    Turbo::StreamsChannel.broadcast_replace_to(
      [conversation.user, :assistant],
      target: "#{conversation.dom_id_for_panel}_status",
      html: %(<span id="#{conversation.dom_id_for_panel}_status" class="text-xs text-content-muted animate-pulse">Thinking…</span>)
    )
  end
end
