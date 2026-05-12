require "test_helper"

module Runners
  class ClaudeCLITest < ActiveSupport::TestCase
    setup do
      @runner = Runners::ClaudeCLI.new
    end

    test "build_cmd produces a -p invocation with the given prompt" do
      cmd = @runner.build_cmd(prompt: "do the thing")
      assert_equal "claude", cmd.first
      assert_includes cmd, "-p"
      assert_includes cmd, "do the thing"
    end

    test "build_cmd in streaming mode adds --output-format stream-json and --verbose" do
      cmd = @runner.build_cmd(prompt: "x", stream: true)
      assert_includes cmd, "--output-format"
      idx = cmd.index("--output-format")
      assert_equal "stream-json", cmd[idx + 1]
      assert_includes cmd, "--verbose"
    end

    test "build_cmd resume mode uses --resume with the supplied resume_message" do
      cmd = @runner.build_cmd(
        prompt: nil,
        resume_session_id: "abc-123",
        resume_message: "fix the schema",
        stream: false
      )
      assert_includes cmd, "--resume"
      assert_includes cmd, "abc-123"
      assert_includes cmd, "fix the schema"
    end

    test "build_cmd resume mode falls back to a default continue message when none given" do
      cmd = @runner.build_cmd(prompt: nil, resume_session_id: "sid")
      fallback = cmd.find { |s| s.is_a?(String) && s.include?("Continue and complete the task") }
      assert fallback, "Expected fallback resume message in cmd: #{cmd.inspect}"
    end

    test "build_cmd passes --model when provided" do
      cmd = @runner.build_cmd(prompt: "x", model: "claude-opus-4-7")
      idx = cmd.index("--model")
      assert idx, "Expected --model in cmd"
      assert_equal "claude-opus-4-7", cmd[idx + 1]
    end

    test "build_cmd omits --model when nil" do
      cmd = @runner.build_cmd(prompt: "x")
      assert_not_includes cmd, "--model"
    end

    test "build_cmd passes --max-turns when provided" do
      cmd = @runner.build_cmd(prompt: "x", max_turns: 5)
      idx = cmd.index("--max-turns")
      assert idx
      assert_equal "5", cmd[idx + 1]
    end

    test "build_cmd defaults --effort to medium when blank" do
      cmd = @runner.build_cmd(prompt: "x", effort: nil)
      idx = cmd.index("--effort")
      assert idx
      assert_equal "medium", cmd[idx + 1]
    end

    test "build_cmd uses --dangerously-skip-permissions when requested" do
      cmd = @runner.build_cmd(prompt: "x", dangerously_skip_permissions: true, allowed_tools: "Read")
      assert_includes cmd, "--dangerously-skip-permissions"
      assert_not_includes cmd, "--permission-mode"
      assert_not_includes cmd, "--allowedTools"
    end

    test "build_cmd uses --permission-mode and --allowedTools when not skipping" do
      cmd = @runner.build_cmd(prompt: "x", allowed_tools: "Bash,Read")
      idx = cmd.index("--permission-mode")
      assert_equal "dontAsk", cmd[idx + 1]
      tools_idx = cmd.index("--allowedTools")
      assert_equal "Bash,Read", cmd[tools_idx + 1]
    end

    test "build_cmd appends --add-dir for each entry in add_dirs" do
      cmd = @runner.build_cmd(prompt: "x", add_dirs: ["/a", "/b"])
      add_dir_indexes = cmd.each_index.select { |i| cmd[i] == "--add-dir" }
      assert_equal 2, add_dir_indexes.size
      assert_equal "/a", cmd[add_dir_indexes[0] + 1]
      assert_equal "/b", cmd[add_dir_indexes[1] + 1]
    end

    test "build_cmd silently ignores unknown kwargs like cwd and env" do
      cmd = @runner.build_cmd(prompt: "x", cwd: "/tmp", env: { "FOO" => "bar" })
      assert_equal "claude", cmd.first
      assert_includes cmd, "x"
    end
  end
end
