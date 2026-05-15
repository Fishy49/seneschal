require "test_helper"

# rubocop:disable Style/ClassAndModuleChildren
class StepExecutor::PrCreatorTest < ActiveSupport::TestCase # rubocop:disable Metrics/ClassLength
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
      ["git", "push", "-u"] => stub_response(success: true),
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

  # Regression: a fresh Seneschal worktree branches `seneschal/run-<id>`
  # locally off origin/HEAD — that branch only exists on the operator's
  # machine, not on origin, until something pushes it. `gh pr create`
  # aborts with "you must first push the current branch to a remote, or
  # use the --head flag" if the ref isn't reachable on origin. The step
  # now pushes unconditionally before calling gh pr create.
  test "pushes the local branch to origin before gh pr create" do
    push_argv = nil
    push_then_create_order = []
    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: "[]", success: true),
      ["git", "rev-parse"] => stub_response(stdout: "seneschal/run-30\n", success: true),
      ["git", "push", "-u"] => lambda { |*argv|
        push_argv = argv
        push_then_create_order << :push
        ["", "", success_status]
      },
      ["gh", "pr", "create"] => lambda { |*_argv|
        push_then_create_order << :create
        ["https://github.com/test/seneschal/pull/42\n", "", success_status]
      }
    ) do
      result = StepExecutor.new(@step, { "task_title" => "x", "task_body" => "y" },
                                @project.local_path).execute
      assert result.passed?, result.stderr
    end

    assert push_argv, "git push -u must run before gh pr create"
    assert_equal ["git", "push", "-u", "origin", "seneschal/run-30"], push_argv.first(5)
    assert_equal [:push, :create], push_then_create_order
  end

  test "fails cleanly when the pre-create push fails" do
    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: "[]", success: true),
      ["git", "rev-parse"] => stub_response(stdout: "feature/foo\n", success: true),
      ["git", "push", "-u"] => stub_response(stderr: "rejected (non-fast-forward)", success: false),
      ["gh", "pr", "create"] => lambda { |*_argv|
        flunk "gh pr create should not run when the push failed"
      }
    ) do
      result = StepExecutor.new(@step, { "task_title" => "x", "task_body" => "y" },
                                @project.local_path).execute
      assert_not result.passed?
      assert_includes result.stderr, "Failed to push local feature/foo"
      assert_includes result.stderr, "non-fast-forward"
    end
  end

  test "interpolated title and body do not get re-escaped when passing to gh" do
    captured_argv = nil
    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: "[]", success: true),
      ["git", "rev-parse"] => stub_response(stdout: "feature/foo\n", success: true),
      ["git", "push", "-u"] => stub_response(success: true),
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
      ["git", "push", "-u"] => stub_response(success: true),
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

  test "appends --reviewer, --label, and --assignee per array entry" do # rubocop:disable Metrics/BlockLength
    @step.update!(config: @step.config.merge(
      "reviewers" => ["alice", "my-org/backend-team"],
      "labels" => ["feature", "needs-review"],
      "assignees" => ["bob"]
    ))

    captured_argv = nil
    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: "[]", success: true),
      ["git", "rev-parse"] => stub_response(stdout: "feature/foo\n", success: true),
      ["git", "push", "-u"] => stub_response(success: true),
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
      ["git", "push", "-u"] => stub_response(success: true),
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
      ["git", "push", "-u"] => stub_response(success: true),
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
      ["git", "push", "-u"] => stub_response(success: true),
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
      ["git", "push", "-u"] => stub_response(success: true),
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

  # ---- clean: true (destructive re-create) ----

  test "clean=true closes existing PR, wipes remote branch, pushes local, then creates fresh" do # rubocop:disable Metrics/BlockLength
    @step.update!(config: @step.config.merge("clean" => true))
    list_payload = JSON.dump([{ "number" => 7, "url" => "https://github.com/test/seneschal/pull/7" }])

    close_argv = nil
    delete_argv = nil
    push_argv = nil
    create_called = false
    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: list_payload, success: true),
      ["git", "rev-parse"] => stub_response(stdout: "feature/foo\n", success: true),
      ["gh", "pr", "close"] => lambda { |*argv|
        close_argv = argv
        ["", "", success_status]
      },
      ["git", "push", "--delete"] => lambda { |*argv|
        delete_argv = argv
        ["", "", success_status]
      },
      ["git", "push", "-u"] => lambda { |*argv|
        push_argv = argv
        ["", "", success_status]
      },
      ["gh", "pr", "create"] => lambda { |*_argv|
        create_called = true
        ["https://github.com/test/seneschal/pull/42\n", "", success_status]
      }
    ) do
      result = StepExecutor.new(@step, { "task_title" => "x", "task_body" => "y" },
                                @project.local_path).execute
      assert result.passed?, result.stderr
      assert_includes result.stdout, "::set-output pr_number=42",
                      "expected fresh PR #42, not the reused #7"
    end

    assert create_called, "gh pr create should run after the clean path completes"
    assert close_argv, "gh pr close should have been invoked"
    assert_includes close_argv, "7"
    comment_idx = close_argv.index("--comment")
    assert comment_idx, "gh pr close should pass --comment"
    assert_match(/Superseded by Seneschal/, close_argv[comment_idx + 1])

    assert delete_argv, "git push --delete should have been invoked"
    assert_equal ["git", "push", "--delete", "origin", "feature/foo"], delete_argv.first(5)
    assert_equal ["git", "push", "-u", "origin", "feature/foo"], push_argv.first(5)
  end

  test "clean=true closes every open PR on the branch, not just the first" do
    @step.update!(config: @step.config.merge("clean" => true))
    list_payload = JSON.dump([
                               { "number" => 7, "url" => "https://github.com/test/seneschal/pull/7" },
                               { "number" => 8, "url" => "https://github.com/test/seneschal/pull/8" }
                             ])

    closed_numbers = []
    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: list_payload, success: true),
      ["git", "rev-parse"] => stub_response(stdout: "feature/foo\n", success: true),
      ["gh", "pr", "close"] => lambda { |*argv|
        closed_numbers << argv[3] # gh pr close <number> ...
        ["", "", success_status]
      },
      ["git", "push", "--delete"] => stub_response(success: true),
      ["git", "push", "-u"] => stub_response(success: true),
      ["gh", "pr", "create"] => stub_response(stdout: "https://github.com/test/seneschal/pull/42\n", success: true)
    ) do
      result = StepExecutor.new(@step, { "task_title" => "x", "task_body" => "y" },
                                @project.local_path).execute
      assert result.passed?, result.stderr
    end

    assert_equal ["7", "8"], closed_numbers
  end

  test "clean=true tolerates git push --delete failure when the remote ref is already gone" do
    @step.update!(config: @step.config.merge("clean" => true))
    list_payload = JSON.dump([{ "number" => 7, "url" => "https://github.com/test/seneschal/pull/7" }])

    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: list_payload, success: true),
      ["git", "rev-parse"] => stub_response(stdout: "feature/foo\n", success: true),
      ["gh", "pr", "close"] => stub_response(success: true),
      ["git", "push", "--delete"] => stub_response(
        stderr: "error: unable to delete 'feature/foo': remote ref does not exist", success: false
      ),
      ["git", "push", "-u"] => stub_response(success: true),
      ["gh", "pr", "create"] => stub_response(stdout: "https://github.com/test/seneschal/pull/42\n", success: true)
    ) do
      result = StepExecutor.new(@step, { "task_title" => "x", "task_body" => "y" },
                                @project.local_path).execute
      assert result.passed?, "delete-ref failure must not abort the clean flow: #{result.stderr}"
    end
  end

  test "clean=true aborts when gh pr close fails" do
    @step.update!(config: @step.config.merge("clean" => true))
    list_payload = JSON.dump([{ "number" => 7, "url" => "https://github.com/test/seneschal/pull/7" }])

    create_called = false
    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: list_payload, success: true),
      ["git", "rev-parse"] => stub_response(stdout: "feature/foo\n", success: true),
      ["git", "push", "-u"] => stub_response(success: true),
      ["gh", "pr", "close"] => stub_response(stderr: "remote: forbidden", success: false),
      ["gh", "pr", "create"] => lambda { |*_argv|
        create_called = true
        ["", "", success_status]
      }
    ) do
      result = StepExecutor.new(@step, { "task_title" => "x", "task_body" => "y" },
                                @project.local_path).execute
      assert_not result.passed?
      assert_includes result.stderr, "Failed to close PR #7"
      assert_includes result.stderr, "forbidden"
    end

    assert_not create_called, "gh pr create should not run if the close step failed"
  end

  test "clean=true is a no-op on the close/wipe path when no PR exists yet" do
    @step.update!(config: @step.config.merge("clean" => true))

    close_called = false
    delete_called = false
    with_stubbed_capture3(
      ["gh", "pr", "list"] => stub_response(stdout: "[]", success: true),
      ["git", "rev-parse"] => stub_response(stdout: "feature/foo\n", success: true),
      ["git", "push", "-u"] => stub_response(success: true),
      ["gh", "pr", "close"] => lambda { |*_argv|
        close_called = true
        ["", "", success_status]
      },
      ["git", "push", "--delete"] => lambda { |*_argv|
        delete_called = true
        ["", "", success_status]
      },
      ["gh", "pr", "create"] => stub_response(stdout: "https://github.com/test/seneschal/pull/42\n", success: true)
    ) do
      result = StepExecutor.new(@step, { "task_title" => "x", "task_body" => "y" },
                                @project.local_path).execute
      assert result.passed?, result.stderr
    end

    assert_not close_called, "no PR to close → don't call gh pr close"
    assert_not delete_called, "no PR to clean → don't wipe remote"
  end

  test "refuses an unsafe branch name before any git/gh call" do
    @step.update!(config: @step.config.merge("branch" => "--upload-pack=evil"))

    any_call = false
    with_stubbed_capture3(
      ["gh", "pr", "list"] => lambda { |*_a|
        any_call = true
        ["[]", "", success_status]
      },
      ["gh", "pr", "create"] => lambda { |*_a|
        any_call = true
        ["", "", success_status]
      }
    ) do
      result = StepExecutor.new(@step, { "task_title" => "x", "task_body" => "y" },
                                @project.local_path).execute
      assert_not result.passed?
      assert_includes result.stderr, "not a safe git ref name"
    end

    assert_not any_call, "no gh/git command should run when the branch is rejected"
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
