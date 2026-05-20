require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

module Runners
  class ClaudeSDKTest < ActiveSupport::TestCase
    setup do
      @runner = Runners::ClaudeSDK.new
      @tmpdir = Dir.mktmpdir("seneschal-sdk-runner-test-")
      # cwd has to be a real directory or Open3.popen3(chdir:) raises before
      # we ever see the fake script's output.
      @cwd = @tmpdir
    end

    teardown do
      FileUtils.rm_rf(@tmpdir) if @tmpdir
      Setting.find_by(key: "python_bin")&.destroy
      Setting.find_by(key: "sdk_runner_script")&.destroy
    end

    # ---- capabilities ----

    test "advertises native structured-output support" do
      assert_predicate @runner, :supports_structured_outputs?
    end

    test "ClaudeCLI does NOT advertise structured-output support" do
      assert_not_predicate Runners::ClaudeCLI.new, :supports_structured_outputs?
    end

    # ---- build_config ----

    test "build_config carries the prompt, cwd, model, max_turns through verbatim" do
      cfg = @runner.build_config(
        prompt: "do the thing", cwd: "/tmp",
        model: "claude-opus-4-7", max_turns: 5, effort: "high"
      )
      assert_equal "do the thing", cfg["prompt"]
      assert_equal "/tmp", cfg["cwd"]
      assert_equal "claude-opus-4-7", cfg["model"]
      assert_equal 5, cfg["max_turns"]
      assert_equal "high", cfg["effort"]
    end

    test "build_config normalizes a comma-separated allowed_tools string into an array" do
      cfg = @runner.build_config(prompt: "x", cwd: "/tmp", allowed_tools: "Bash, Read,  Edit ")
      assert_equal ["Bash", "Read", "Edit"], cfg["allowed_tools"]
    end

    test "build_config preserves an allowed_tools array as-is" do
      cfg = @runner.build_config(prompt: "x", cwd: "/tmp", allowed_tools: ["Bash", "Read"])
      assert_equal ["Bash", "Read"], cfg["allowed_tools"]
    end

    test "build_config passes through resume_session_id and resume_message" do
      cfg = @runner.build_config(
        prompt: nil, cwd: "/tmp",
        resume_session_id: "sess-1", resume_message: "fix the schema"
      )
      assert_equal "sess-1", cfg["resume_session_id"]
      assert_equal "fix the schema", cfg["resume_message"]
    end

    test "build_config defaults dangerously_skip_permissions to false" do
      cfg = @runner.build_config(prompt: "x", cwd: "/tmp")
      assert_equal false, cfg["dangerously_skip_permissions"]
    end

    test "build_config wraps a scalar add_dirs into an array" do
      cfg = @runner.build_config(prompt: "x", cwd: "/tmp", add_dirs: "/single")
      assert_equal ["/single"], cfg["add_dirs"]
    end

    # ---- python_bin resolution ----

    test "python_bin honors the Setting override" do
      Setting["python_bin"] = "/opt/custom/python"
      assert_equal "/opt/custom/python", @runner.python_bin
    end

    test "python_bin prefers the bundled venv when present and no override is set" do
      Setting.find_by(key: "python_bin")&.destroy
      stub_file_executable!(true) do
        assert_equal Runners::ClaudeSDK::BUNDLED_VENV_PYTHON, @runner.python_bin
      end
    end

    test "python_bin falls back to system python3 when neither override nor venv exists" do
      Setting.find_by(key: "python_bin")&.destroy
      stub_file_executable!(false) do
        assert_equal Runners::ClaudeSDK::DEFAULT_PYTHON_BIN, @runner.python_bin
      end
    end

    # ---- runner_script resolution + missing-script guard ----

    test "execute raises SdkRunnerMissing when the configured script doesn't exist" do
      Setting["sdk_runner_script"] = "/no/such/script.py"
      assert_raises(Runners::ClaudeSDK::SdkRunnerMissing) do
        @runner.execute(prompt: "x", cwd: @cwd)
      end
    end

    # ---- end-to-end with a fake Python interpreter ----

    test "buffered execute sends config to the script on stdin and parses NDJSON result" do
      fake_python, capture_path = install_fake_python(:echo_then_result)
      Setting["python_bin"] = fake_python
      Setting["sdk_runner_script"] = make_dummy_script

      result = @runner.execute(prompt: "hello world", cwd: @cwd, model: "claude-opus-4-7")

      assert_equal 0, result.exit_code
      assert_equal "Done", result.stdout
      assert_equal "sess_fake", result.session_id
      # The fake echoes the inbound config to a capture file — verify
      # the Ruby side serialized the kwargs correctly.
      captured = JSON.parse(File.read(capture_path))
      assert_equal "hello world", captured["prompt"]
      assert_equal "claude-opus-4-7", captured["model"]
    end

    test "streaming execute yields progress hashes containing the latest event list" do
      fake_python, = install_fake_python(:streaming_three_events)
      Setting["python_bin"] = fake_python
      Setting["sdk_runner_script"] = make_dummy_script

      updates = []
      result = @runner.execute(prompt: "x", cwd: @cwd, stream: true) do |update|
        updates << update
      end

      assert_equal 0, result.exit_code
      assert_equal "final answer", result.stdout
      assert_equal "sess_stream", result.session_id
      assert result.stream_events.is_a?(Array)
      assert_operator result.stream_events.size, :>=, 3
      # At minimum the runner should fire the closing yield with all events.
      assert updates.any?, "expected at least one progress yield"
      assert_includes updates.last[:output].to_s, "final answer"
    end

    # RunStep#usage_stats reads cost + token counts straight off the last
    # `result` event in stream_log. If the SDK runner's serializer ever
    # drops the `usage` sub-object or any of the documented keys, the
    # cost/token displays in the UI would silently zero out. This test
    # nails down the wire-format contract end-to-end.
    test "result event preserves cost + usage telemetry so RunStep#usage_stats keeps working" do
      fake_python, = install_fake_python(:full_telemetry_result)
      Setting["python_bin"] = fake_python
      Setting["sdk_runner_script"] = make_dummy_script

      result = @runner.execute(prompt: "x", cwd: @cwd)

      result_event = result.stream_events.reverse.find { |e| e["type"] == "result" }
      assert_in_delta 0.0421, result_event["total_cost_usd"], 0.0001
      assert_equal 4, result_event["num_turns"]
      assert_equal 12_345, result_event["duration_ms"]

      usage = result_event["usage"]
      assert_kind_of Hash, usage
      assert_equal 1_500, usage["input_tokens"]
      assert_equal 240, usage["output_tokens"]
      assert_equal 800, usage["cache_read_input_tokens"]
      assert_equal 320, usage["cache_creation_input_tokens"]
    end

    test "error events are surfaced into the Result's stderr" do
      fake_python, = install_fake_python(:emit_error)
      Setting["python_bin"] = fake_python
      Setting["sdk_runner_script"] = make_dummy_script

      result = @runner.execute(prompt: "x", cwd: @cwd)

      assert_not_equal 0, result.exit_code
      assert_includes result.stderr.to_s, "claude-agent-sdk is not installed"
    end

    # ---- structured outputs ----

    test "build_config carries json_schema through to the wire payload" do
      schema = { "type" => "object", "properties" => { "pr_number" => { "type" => "integer" } } }
      cfg = @runner.build_config(prompt: "x", cwd: "/tmp", json_schema: schema)
      assert_equal schema, cfg["json_schema"]
    end

    test "build_config sets json_schema to nil when unset" do
      cfg = @runner.build_config(prompt: "x", cwd: "/tmp")
      assert_nil cfg["json_schema"]
    end

    test "json_schema in the wire config reaches the sidecar's stdin" do
      fake_python, capture_path = install_fake_python(:echo_then_result)
      Setting["python_bin"] = fake_python
      Setting["sdk_runner_script"] = make_dummy_script

      schema = { "type" => "object", "properties" => { "branch" => { "type" => "string" } } }
      @runner.execute(prompt: "x", cwd: @cwd, json_schema: schema)

      captured = JSON.parse(File.read(capture_path))
      assert_equal schema, captured["json_schema"]
    end

    test "structured_output is extracted from the result event into Runners::Result" do
      fake_python, = install_fake_python(:result_with_structured_output)
      Setting["python_bin"] = fake_python
      Setting["sdk_runner_script"] = make_dummy_script

      result = @runner.execute(prompt: "x", cwd: @cwd)

      assert_equal({ "pr_number" => 42, "branch" => "feat/x" }, result.structured_output)
    end

    test "structured_output is nil when the SDK didn't emit one (no schema in play)" do
      fake_python, = install_fake_python(:echo_then_result)
      Setting["python_bin"] = fake_python
      Setting["sdk_runner_script"] = make_dummy_script

      result = @runner.execute(prompt: "x", cwd: @cwd)
      assert_nil result.structured_output
    end

    # When the bundled CLI doesn't register StructuredOutput (typically
    # because prompt size pushed it into the deferred-tool set), the
    # sidecar bails at session-init with an explicit error event. The
    # runner must surface that as a failed Result with the explanation
    # in stderr — otherwise the symptom resurfaces downstream as the
    # generic "Output variable was missing" message.
    test "sidecar's structured-output-missing error propagates as a failed Result with diagnostic stderr" do
      fake_python, = install_fake_python(:missing_structured_output)
      Setting["python_bin"] = fake_python
      Setting["sdk_runner_script"] = make_dummy_script

      result = @runner.execute(prompt: "x", cwd: @cwd, json_schema: { "type" => "object" })

      assert_not_predicate result, :passed?
      assert_match(/StructuredOutput tool was not registered.*queryable context/m, result.stderr)
    end

    # ---- hooks passthrough ----

    test "build_config carries the hooks dict to the wire payload" do
      cfg = @runner.build_config(prompt: "x", cwd: "/tmp", hooks: { "confine_writes_to_cwd" => true })
      assert_equal({ "confine_writes_to_cwd" => true }, cfg["hooks"])
    end

    test "build_config defaults hooks to nil when unset" do
      cfg = @runner.build_config(prompt: "x", cwd: "/tmp")
      assert_nil cfg["hooks"]
    end

    test "hooks reach the sidecar's stdin verbatim" do
      fake_python, capture_path = install_fake_python(:echo_then_result)
      Setting["python_bin"] = fake_python
      Setting["sdk_runner_script"] = make_dummy_script

      @runner.execute(prompt: "x", cwd: @cwd, hooks: { "confine_writes_to_cwd" => false })
      captured = JSON.parse(File.read(capture_path))
      assert_equal({ "confine_writes_to_cwd" => false }, captured["hooks"])
    end

    # ---- agents passthrough ----

    test "build_config carries an agents hash to the wire payload" do
      agents = {
        "self-review" => {
          "description" => "Reviews a diff.",
          "prompt" => "You are a code reviewer.",
          "tools" => ["Read", "Grep", "Glob"],
          "model" => "claude-sonnet-4-6"
        }
      }
      cfg = @runner.build_config(prompt: "x", cwd: "/tmp", agents: agents)
      assert_equal agents, cfg["agents"]
    end

    test "build_config defaults agents to nil when unset" do
      cfg = @runner.build_config(prompt: "x", cwd: "/tmp")
      assert_nil cfg["agents"]
    end

    test "agents reach the sidecar's stdin verbatim" do
      fake_python, capture_path = install_fake_python(:echo_then_result)
      Setting["python_bin"] = fake_python
      Setting["sdk_runner_script"] = make_dummy_script

      agents = { "reviewer" => { "description" => "x", "prompt" => "y", "tools" => ["Read"] } }
      @runner.execute(prompt: "x", cwd: @cwd, agents: agents)
      captured = JSON.parse(File.read(capture_path))
      assert_equal agents, captured["agents"]
    end

    # ---- mcp_servers passthrough ----

    test "build_config carries an mcp_servers hash to the wire payload" do
      servers = {
        "github" => {
          "type" => "stdio", "command" => "npx",
          "args" => ["-y", "@modelcontextprotocol/server-github"]
        }
      }
      cfg = @runner.build_config(prompt: "x", cwd: "/tmp", mcp_servers: servers)
      assert_equal servers, cfg["mcp_servers"]
    end

    test "build_config defaults mcp_servers to nil when unset" do
      cfg = @runner.build_config(prompt: "x", cwd: "/tmp")
      assert_nil cfg["mcp_servers"]
    end

    test "mcp_servers reach the sidecar's stdin verbatim" do
      fake_python, capture_path = install_fake_python(:echo_then_result)
      Setting["python_bin"] = fake_python
      Setting["sdk_runner_script"] = make_dummy_script

      servers = { "linear" => { "type" => "http", "url" => "https://example.com/mcp" } }
      @runner.execute(prompt: "x", cwd: @cwd, mcp_servers: servers)
      captured = JSON.parse(File.read(capture_path))
      assert_equal servers, captured["mcp_servers"]
    end

    private

    # Writes a Ruby-based fake interpreter to a tempfile and returns its
    # path plus a capture file path (where it dumps the inbound stdin
    # so the test can assert on what got sent). The fake ignores its
    # script argument and just reads stdin / emits scripted NDJSON.
    def install_fake_python(behavior)
      capture = File.join(@tmpdir, "captured-config.json")
      script = File.join(@tmpdir, "fake_python")

      File.write(script, fake_python_body(behavior, capture))
      File.chmod(0o755, script)
      [script, capture]
    end

    def fake_python_body(behavior, capture_path)
      <<~RUBY
        #!/usr/bin/env ruby
        # Fake Python interpreter for ClaudeSDK runner tests. Reads stdin,
        # dumps it to #{capture_path}, then emits a scripted sequence of
        # NDJSON events to stdout matching the `claude` CLI wire format.
        require "json"

        config = STDIN.read
        File.write(#{capture_path.inspect}, config)

        case #{behavior.to_s.inspect}
        when "echo_then_result"
          STDOUT.puts JSON.dump({"type"=>"system","session_id"=>"sess_fake","model"=>"claude-opus-4-7"})
          STDOUT.puts JSON.dump({"type"=>"assistant","message"=>{"content"=>[{"type"=>"text","text"=>"Working..."}]},"session_id"=>"sess_fake"})
          STDOUT.puts JSON.dump({"type"=>"result","subtype"=>"success","is_error"=>false,"result"=>"Done","session_id"=>"sess_fake","total_cost_usd"=>0.01,"num_turns"=>1,"duration_ms"=>500})
          exit 0
        when "streaming_three_events"
          STDOUT.puts JSON.dump({"type"=>"system","session_id"=>"sess_stream","model"=>"claude-opus-4-7"}); STDOUT.flush
          STDOUT.puts JSON.dump({"type"=>"assistant","message"=>{"content"=>[{"type"=>"text","text"=>"thinking..."}]},"session_id"=>"sess_stream"}); STDOUT.flush
          STDOUT.puts JSON.dump({"type"=>"assistant","message"=>{"content"=>[{"type"=>"text","text"=>"final answer"}]},"session_id"=>"sess_stream"}); STDOUT.flush
          STDOUT.puts JSON.dump({"type"=>"result","subtype"=>"success","is_error"=>false,"result"=>"final answer","session_id"=>"sess_stream","total_cost_usd"=>0.02,"num_turns"=>2,"duration_ms"=>800}); STDOUT.flush
          exit 0
        when "emit_error"
          STDOUT.puts JSON.dump({"type"=>"error","message"=>"claude-agent-sdk is not installed in this Python environment"})
          exit 1
        when "full_telemetry_result"
          STDOUT.puts JSON.dump({
            "type"=>"result", "subtype"=>"success", "is_error"=>false,
            "result"=>"Done.", "session_id"=>"sess_telem",
            "total_cost_usd"=>0.0421, "num_turns"=>4,
            "duration_ms"=>12_345, "duration_api_ms"=>11_900,
            "usage"=>{
              "input_tokens"=>1_500, "output_tokens"=>240,
              "cache_read_input_tokens"=>800, "cache_creation_input_tokens"=>320
            }
          })
          exit 0
        when "result_with_structured_output"
          STDOUT.puts JSON.dump({
            "type"=>"result", "subtype"=>"success", "is_error"=>false,
            "result"=>"", "session_id"=>"sess_struct",
            "structured_output"=>{"pr_number"=>42, "branch"=>"feat/x"}
          })
          exit 0
        when "missing_structured_output"
          STDOUT.puts JSON.dump({
            "type"=>"error",
            "message"=>"StructuredOutput tool was not registered for this session even though a json_schema was configured. The bundled `claude` CLI exposed these tools instead: [\\"Read\\", \\"Edit\\"]. This typically means the prompt is large enough that the CLI deferred the structured-output tool. Shrink the prompt — for example, route large `consumes` payloads through queryable context (seneschal-context CLI) instead of inlining them — and re-run."
          })
          exit 1
        end
      RUBY
    end

    # Touch a dummy script file at a real path so ensure_runner_script!'s
    # existence check passes. Contents don't matter — the fake interpreter
    # doesn't actually execute it.
    def make_dummy_script
      path = File.join(@tmpdir, "fake_runner.py")
      File.write(path, "# placeholder for test\n")
      path
    end

    # Same alias_method pattern as worktree_reaper_job_test.rb — used here
    # to stub File.executable? for the python_bin resolution tests, since
    # the dev box may or may not have the bundled venv installed.
    def stub_file_executable!(return_value)
      mc = File.singleton_class
      mc.send(:alias_method, :__orig_executable?, :executable?)
      mc.send(:define_method, :executable?) { |_path| return_value }
      yield
    ensure
      mc.send(:remove_method, :executable?)
      mc.send(:alias_method, :executable?, :__orig_executable?)
      mc.send(:remove_method, :__orig_executable?)
    end
  end
end
