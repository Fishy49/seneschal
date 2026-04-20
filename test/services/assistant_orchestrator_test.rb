require "test_helper"

class AssistantOrchestratorTest < ActiveSupport::TestCase
  setup do
    @conversation = assistant_conversations(:admin_conversation)
  end

  test "run returns output and events on success" do
    fake_output = "#{[
      { "type" => "assistant", "session_id" => "sess_abc",
        "message" => { "content" => [{ "type" => "text", "text" => "Hello from assistant" }] } }.to_json,
      { "type" => "result", "result" => "Hello from assistant", "session_id" => "sess_abc" }.to_json
    ].join("\n")}\n"

    stub_popen3(stdout: fake_output, exit_code: 0) do
      orchestrator = AssistantOrchestrator.new(@conversation)
      result = orchestrator.run("test message")

      assert_equal "Hello from assistant", result[:output]
      assert_equal "sess_abc", result[:claude_session_id]
      assert_kind_of Array, result[:events]
    end
  end

  test "run handles JSON parse errors gracefully" do
    fake_output = "not json\n{\"type\":\"result\",\"result\":\"ok\",\"session_id\":\"sess_1\"}\n"

    stub_popen3(stdout: fake_output, exit_code: 0) do
      orchestrator = AssistantOrchestrator.new(@conversation)
      result = orchestrator.run("test")
      assert_equal "ok", result[:output]
    end
  end

  test "run handles popen3 errors" do
    Open3.stub(:popen3, ->(*_args, **_kwargs) { raise Errno::ENOENT, "claude not found" }) do
      orchestrator = AssistantOrchestrator.new(@conversation)
      result = orchestrator.run("test")
      assert result[:error].present?
    end
  end

  test "prompt includes page context when last_page_path is set" do
    @conversation.update!(last_page_path: "/projects/#{projects(:seneschal).id}")
    prompt_built = nil
    AssistantPromptBuilder.stub(:new, lambda { |conv, msg|
      obj = AssistantPromptBuilder.allocate
      obj.instance_variable_set(:@conversation, conv)
      obj.instance_variable_set(:@user_message, msg)
      mock = Object.new
      mock.define_singleton_method(:build) do
        prompt_built = obj.send(:page_context_section)
        "prompt text"
      end
      mock
    }) do
      stub_popen3(stdout: "{\"type\":\"result\",\"result\":\"done\",\"session_id\":\"s\"}\n", exit_code: 0) do
        orchestrator = AssistantOrchestrator.new(@conversation)
        orchestrator.run("hello")
      end
    end

    assert prompt_built&.include?(projects(:seneschal).name)
  end

  private

  def stub_popen3(stdout:, exit_code:, &)
    stdin_mock = StringIO.new
    stdin_mock.define_singleton_method(:close) { nil }
    stdout_mock = StringIO.new(stdout)
    stderr_mock = StringIO.new("")
    wait_mock = Minitest::Mock.new
    status_mock = Minitest::Mock.new
    status_mock.expect(:exitstatus, exit_code)
    wait_mock.expect(:value, status_mock)

    Open3.stub(:popen3, lambda { |*_args, **_kwargs, &blk|
      blk.call(stdin_mock, stdout_mock, stderr_mock, wait_mock)
    }, &)
  end
end
