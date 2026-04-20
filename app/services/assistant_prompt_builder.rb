class AssistantPromptBuilder
  SYSTEM_PROMPT = <<~SYSTEM.freeze
    You are Seneschal's built-in assistant. Seneschal is a workflow orchestration tool that manages AI pipelines with skills, steps, and runs.

    To take actions, call the HTTP API using Bash(curl ...). The API base URL and bearer token are available as environment variables:
      - $ASSISTANT_API_BASE — base URL for the internal API
      - $ASSISTANT_API_TOKEN — bearer token for authentication

    Always use: curl -s -H "Authorization: Bearer $ASSISTANT_API_TOKEN" ...

    Guidelines:
    - To present button choices to the user, call POST $ASSISTANT_API_BASE/ui/ask_choices
    - To ask a freeform question, call POST $ASSISTANT_API_BASE/ui/ask_text
    - To send the user to a page, call POST $ASSISTANT_API_BASE/ui/navigate
    - Always prefer a single ui/* call to end your turn
    - When creating workflows, confirm intent via ask_text, create the workflow, add steps, then navigate to the result
    - Never include secrets or passwords in responses
  SYSTEM

  def initialize(conversation, user_message)
    @conversation = conversation
    @user_message = user_message
  end

  def build
    parts = [SYSTEM_PROMPT]
    parts << tool_catalog_section
    parts << page_context_section if @conversation.last_page_path.present?
    parts << conversation_history_section
    parts << "## User\n\n#{@user_message}"
    parts.join("\n\n")
  end

  private

  def tool_catalog_section
    "## Available API\n\n#{AssistantToolCatalog.markdown}"
  end

  def page_context_section
    context = AssistantPageContext.summarize(@conversation.last_page_path)
    "## Current Page Context\n\n```json\n#{JSON.pretty_generate(context)}\n```"
  end

  def conversation_history_section
    messages = @conversation.assistant_messages.last(20).to_a
    return "" if messages.empty?

    lines = messages.map do |m|
      "### #{m.role.capitalize}\n\n#{m.content}"
    end
    "## Conversation History\n\n#{lines.join("\n\n")}"
  end
end
