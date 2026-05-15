require "test_helper"

# rubocop:disable Style/ClassAndModuleChildren
class StepExecutor::PrCreatorTest < ActiveSupport::TestCase
  # rubocop:enable Style/ClassAndModuleChildren
  setup do
    @project = projects(:seneschal)
    FileUtils.mkdir_p(@project.local_path)
    @workflow = workflows(:deploy)
    @step = @workflow.steps.create!(
      name: "Open PR",
      step_type: "pr",
      position: 99,
      timeout: 60,
      max_retries: 0,
      config: {
        "title" => "feat: ${task_title}",
        "body" => "## Summary\n\n${task_body}",
        "base" => "main",
        "draft" => true
      }
    )
  end

  test "creates a PR via gh and parses pr_number + pr_url" do # rubocop:disable Metrics/BlockLength
    captured_argv = nil
    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: "[]", success: true),
      ["git", "rev-parse"] => stub_response(stdout: "feature/foo\n", success: true),
      ["gh", "pr", "create"] => lambda { |*argv|
        captured_argv = argv
        ["https://github.com/test/seneschal/pull/42\n", "", success_status]
      }
    ) do
      result = StepExecutor.new(@step, { "task_title" => "Add auth", "task_body" => "Login flow" },
                                @project.local_path).execute
      assert result.passed?, result.stderr
      assert_includes result.stdout, "::set-output pr_number=42"
      assert_includes result.stdout, "::set-output pr_url=https://github.com/test/seneschal/pull/42"
      assert_includes result.stdout, "::set-output branch_name=feature/foo"
    end

    assert captured_argv, "gh pr create was not invoked"
    assert_equal "gh", captured_argv[0]
    assert_equal "pr", captured_argv[1]
    assert_equal "create", captured_argv[2]
    # Each arg lives in its own slot — no shell interpolation needed.
    title_idx = captured_argv.index("--title")
    assert title_idx, "--title flag missing"
    assert_equal "feat: Add auth", captured_argv[title_idx + 1]

    body_idx = captured_argv.index("--body")
    assert body_idx, "--body flag missing"
    assert_equal "## Summary\n\nLogin flow", captured_argv[body_idx + 1]

    base_idx = captured_argv.index("--base")
    assert_equal "main", captured_argv[base_idx + 1]

    assert_includes captured_argv, "--draft"
  end

  test "interpolated title and body do not get re-escaped when passing to gh" do
    captured_argv = nil
    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: "[]", success: true),
      ["git", "rev-parse"] => stub_response(stdout: "feature/foo\n", success: true),
      ["gh", "pr", "create"] => lambda { |*argv|
        captured_argv = argv
        ["https://github.com/test/seneschal/pull/3\n", "", success_status]
      }
    ) do
      tricky = "Title with $shell `backticks` and \"quotes\" and; semicolons"
      ctx = { "task_title" => tricky, "task_body" => "$(rm -rf /)" }
      result = StepExecutor.new(@step, ctx, @project.local_path).execute
      assert result.passed?, result.stderr
    end

    title_idx = captured_argv.index("--title")
    # Title flows through verbatim — no shell tokens interpreted, because we
    # bypass bash and call gh with explicit argv.
    assert_equal "feat: Title with $shell `backticks` and \"quotes\" and; semicolons",
                 captured_argv[title_idx + 1]

    body_idx = captured_argv.index("--body")
    assert_equal "## Summary\n\n$(rm -rf /)", captured_argv[body_idx + 1]
  end

  test "skips creation and reuses existing PR for the branch" do
    list_payload = JSON.dump([{ "number" => 7, "url" => "https://github.com/test/seneschal/pull/7" }])
    created = false
    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: list_payload, success: true),
      ["git", "rev-parse"] => stub_response(stdout: "feature/foo\n", success: true),
      ["gh", "pr", "create"] => lambda { |*_argv|
        created = true
        ["https://github.com/test/seneschal/pull/99\n", "", success_status]
      }
    ) do
      result = StepExecutor.new(@step, { "task_title" => "x", "task_body" => "y" },
                                @project.local_path).execute
      assert result.passed?, result.stderr
      assert_includes result.stdout, "::set-output pr_number=7"
      assert_includes result.stdout, "::set-output pr_url=https://github.com/test/seneschal/pull/7"
      assert_includes result.stdout, "::set-output branch_name=feature/foo"
    end

    assert_not created, "gh pr create should not run when an existing PR is found"
  end

  test "appends --reviewer, --label, and --assignee per array entry" do
    @step.update!(config: @step.config.merge(
      "reviewers" => ["alice", "my-org/backend-team"],
      "labels" => ["feature", "needs-review"],
      "assignees" => ["bob"]
    ))

    captured_argv = nil
    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: "[]", success: true),
      ["git", "rev-parse"] => stub_response(stdout: "feature/foo\n", success: true),
      ["gh", "pr", "create"] => lambda { |*argv|
        captured_argv = argv
        ["https://github.com/test/seneschal/pull/12\n", "", success_status]
      }
    ) do
      StepExecutor.new(@step, { "task_title" => "x", "task_body" => "y" },
                       @project.local_path).execute
    end

    reviewer_indexes = captured_argv.each_index.select { |i| captured_argv[i] == "--reviewer" }
    assert_equal 2, reviewer_indexes.size
    assert_equal "alice", captured_argv[reviewer_indexes[0] + 1]
    assert_equal "my-org/backend-team", captured_argv[reviewer_indexes[1] + 1]

    label_indexes = captured_argv.each_index.select { |i| captured_argv[i] == "--label" }
    assert_equal(["feature", "needs-review"], label_indexes.map { |i| captured_argv[i + 1] })

    assignee_indexes = captured_argv.each_index.select { |i| captured_argv[i] == "--assignee" }
    assert_equal(["bob"], assignee_indexes.map { |i| captured_argv[i + 1] })
  end

  test "omits --draft when config draft is false" do
    @step.update!(config: @step.config.merge("draft" => false))
    captured_argv = nil
    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: "[]", success: true),
      ["git", "rev-parse"] => stub_response(stdout: "feature/foo\n", success: true),
      ["gh", "pr", "create"] => lambda { |*argv|
        captured_argv = argv
        ["https://github.com/test/seneschal/pull/1\n", "", success_status]
      }
    ) do
      StepExecutor.new(@step, { "task_title" => "x", "task_body" => "y" },
                       @project.local_path).execute
    end

    assert_not_includes captured_argv, "--draft"
  end

  test "fails when title is blank after interpolation" do
    # Bypass model validation to simulate a config that survived (e.g. older
    # row) but resolves to a blank title at run time.
    @step.update_columns(config: @step.config.merge("title" => "   ")) # rubocop:disable Rails/SkipsModelValidations

    result = StepExecutor.new(@step, {}, @project.local_path).execute
    assert_not result.passed?
    assert_includes result.stderr, "PR step requires a non-empty title"
  end

  test "fails cleanly when gh pr create exits non-zero" do
    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: "[]", success: true),
      ["git", "rev-parse"] => stub_response(stdout: "feature/foo\n", success: true),
      ["gh", "pr", "create"] => stub_response(stdout: "", stderr: "remote: forbidden", success: false)
    ) do
      result = StepExecutor.new(@step, { "task_title" => "x", "task_body" => "y" },
                                @project.local_path).execute
      assert_not result.passed?
      assert_includes result.stderr, "forbidden"
    end
  end

  test "fails when gh stdout has no parseable PR URL" do
    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: "[]", success: true),
      ["git", "rev-parse"] => stub_response(stdout: "feature/foo\n", success: true),
      ["gh", "pr", "create"] => stub_response(stdout: "warning: no upstream\n", success: true)
    ) do
      result = StepExecutor.new(@step, { "task_title" => "x", "task_body" => "y" },
                                @project.local_path).execute
      assert_not result.passed?
      assert_includes result.stderr, "Could not parse PR URL"
    end
  end

  test "honors explicit branch override in config" do
    @step.update!(config: @step.config.merge("branch" => "release/v2"))
    captured_list_argv = nil
    captured_create_argv = nil
    with_stubbed_capture3(
      ["gh", "pr", "list"] => lambda { |*argv|
        captured_list_argv = argv
        ["[]", "", success_status]
      },
      ["git", "rev-parse"] => lambda { |*_argv|
        flunk "should not consult git when branch is explicit"
      },
      ["gh", "pr", "create"] => lambda { |*argv|
        captured_create_argv = argv
        ["https://github.com/test/seneschal/pull/8\n", "", success_status]
      }
    ) do
      result = StepExecutor.new(@step, { "task_title" => "x", "task_body" => "y" },
                                @project.local_path).execute
      assert result.passed?, result.stderr
      assert_includes result.stdout, "::set-output branch_name=release/v2"
    end

    head_idx = captured_list_argv.index("--head")
    assert_equal "release/v2", captured_list_argv[head_idx + 1]
    assert captured_create_argv
  end

  test "PipelineExtractor extracts the conventional outputs from a pr step result" do
    result_stdout = <<~OUT
      ::set-output pr_number=99
      ::set-output pr_url=https://github.com/test/seneschal/pull/99
      ::set-output branch_name=feature/foo

      https://github.com/test/seneschal/pull/99
    OUT

    extracted = PipelineExtractor.new(@step, result_stdout).extract
    assert_equal "99", extracted["pr_number"]
    assert_equal "https://github.com/test/seneschal/pull/99", extracted["pr_url"]
    assert_equal "feature/foo", extracted["branch_name"]
  end

  private

  # Stub Open3.capture3 with a routing table keyed by the first 2-3 argv
  # tokens. Values are either a static [stdout, stderr, status] triplet
  # (built via stub_response) or a lambda that receives the same args
  # Open3.capture3 was called with (sans the env hash) and returns a triplet.
  def with_stubbed_capture3(routes)
    original = Open3.method(:capture3)
    Open3.define_singleton_method(:capture3) do |*args, **kwargs|
      # Drop the env hash if present (first arg can be a Hash for env vars).
      cmd_args = args.dup
      _env = cmd_args.shift if cmd_args.first.is_a?(Hash)

      match = routes.find { |key, _| cmd_args.first(key.size) == key }
      raise "No stub for Open3.capture3 args: #{cmd_args.inspect} (kwargs: #{kwargs.inspect})" unless match

      action = match[1]
      action.respond_to?(:call) ? action.call(*cmd_args) : action
    end
    yield
  ensure
    Open3.define_singleton_method(:capture3, original)
  end

  def stub_response(stdout: "", stderr: "", success: true)
    status = success ? success_status : failure_status
    [stdout, stderr, status]
  end

  def success_status
    @success_status ||= build_status(0)
  end

  def failure_status
    @failure_status ||= build_status(1)
  end

  def build_status(code)
    status = Object.new
    status.define_singleton_method(:success?) { code.zero? }
    status.define_singleton_method(:exitstatus) { code }
    status
  end
end
