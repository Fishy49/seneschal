require "open3"

class AssistantOrchestrator
  BROADCAST_INTERVAL = 2.0
  MAX_EVENTS = 50
  MODEL = "claude-sonnet-4-6".freeze
  ALLOWED_TOOLS = "Bash(curl *) WebFetch".freeze

  def initialize(conversation)
    @conversation = conversation
  end

  def run(user_message, &block)
    prompt = AssistantPromptBuilder.new(@conversation, user_message).build
    cmd = build_cmd(prompt)
    env = build_env

    events = []
    result_text = +""
    stderr_acc = +""
    session_id = nil

    Open3.popen3(env, *cmd, chdir: Rails.root.to_s) do |stdin, stdout, stderr, wait_thr|
      stdin.close
      stderr_thread = Thread.new { stderr_acc = stderr.read }
      last_broadcast = monotonic_now

      stdout.each_line do |line|
        line = line.strip
        next if line.empty?

        event = begin
                  JSON.parse(line)
                rescue JSON::ParserError
                  next
                end

        events << event
        events.shift if events.size > MAX_EVENTS

        session_id ||= event["session_id"]

        case event["type"]
        when "result"
          result_text = event["result"].to_s
          session_id ||= event["session_id"]
        when "assistant"
          (event.dig("message", "content") || []).each do |block|
            result_text = block["text"] if block["type"] == "text"
          end
        end

        if monotonic_now - last_broadcast >= BROADCAST_INTERVAL
          yield({ stream_log: events.dup, output: result_text.dup, claude_session_id: session_id }) if block_given?
          last_broadcast = monotonic_now
        end
      end

      stderr_thread.join
      wait_thr.value

      yield({ stream_log: events.dup, output: result_text.dup, claude_session_id: session_id }) if block_given?
    end

    { output: result_text, events: events, claude_session_id: session_id }
  rescue StandardError => e
    { output: "", events: [], error: e.message, claude_session_id: nil }
  end

  private

  def build_cmd(prompt)
    cmd = ["claude"]
    cmd += ["--resume", @conversation.claude_session_id] if @conversation.claude_session_id.present?
    cmd += ["-p", "--output-format", "stream-json", "--verbose",
            "--model", MODEL,
            "--permission-mode", "dontAsk",
            "--allowedTools", ALLOWED_TOOLS]
    cmd << prompt
    cmd
  end

  def build_env
    base_url = Setting["internal_base_url"].presence || "http://127.0.0.1:3000"
    {
      "ASSISTANT_API_TOKEN" => @conversation.turbo_token.to_s,
      "ASSISTANT_API_BASE" => "#{base_url}/assistant/api"
    }
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
