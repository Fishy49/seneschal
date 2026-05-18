require "test_helper"
require "stringio"
require "tmpdir"
require "fileutils"

class MegaUpdateTest < ActiveSupport::TestCase
  setup do
    @io = StringIO.new

    # Fresh slate — fixtures may include active runs; clear them
    RunStep.where(status: "running").destroy_all
    Run.where(status: ["running", "pending", "awaiting_approval"]).destroy_all
  end

  test "aborts when a pending run exists" do
    workflow = workflows(:deploy)
    workflow.runs.create!(status: "pending", context: {}, input: {})

    summary = MegaUpdate.call(io: @io)

    assert summary.aborted
    assert_includes @io.string, "ABORT"
    assert_includes @io.string, "pending"
  end

  test "aborts when an awaiting_approval run exists" do
    workflow = workflows(:deploy)
    workflow.runs.create!(status: "awaiting_approval", context: {}, input: {})

    summary = MegaUpdate.call(io: @io)
    assert summary.aborted
  end

  test "aborts when a fresh running run exists (recent heartbeat)" do
    workflow = workflows(:deploy)
    run = workflow.runs.create!(status: "running", context: {}, input: {})
    run.update_columns(updated_at: 2.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

    summary = MegaUpdate.call(io: @io, stale_minutes: 30)
    assert summary.aborted
  end

  test "fails a hung run and its still-running RunSteps" do
    workflow = workflows(:deploy)
    run = workflow.runs.create!(status: "running", context: {}, input: {})
    step = workflow.steps.first
    rs = run.run_steps.create!(step: step, status: "running", attempt: 1, position: 1, started_at: 1.hour.ago)
    # Move heartbeat past the stale threshold
    run.update_columns(updated_at: 90.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
    rs.update_columns(updated_at: 90.minutes.ago)  # rubocop:disable Rails/SkipsModelValidations

    summary = MegaUpdate.call(io: @io, stale_minutes: 30)

    assert_not summary.aborted
    assert_equal 1, summary.hung_runs_failed
    assert_equal "failed", run.reload.status
    assert_equal "failed", rs.reload.status
    assert_includes run.error_message, "hung"
  end

  test "fails orphan RunSteps when parent run is terminal" do
    workflow = workflows(:deploy)
    run = workflow.runs.create!(status: "stopped", context: {}, input: {}, finished_at: 1.hour.ago)
    step = workflow.steps.first
    rs = run.run_steps.create!(step: step, status: "running", attempt: 1, position: 1, started_at: 1.hour.ago)

    summary = MegaUpdate.call(io: @io)

    assert_equal 1, summary.orphan_run_steps_failed
    assert_equal "failed", rs.reload.status
  end

  test "dry_run reports actions without changing state" do
    workflow = workflows(:deploy)
    run = workflow.runs.create!(status: "running", context: {}, input: {})
    step = workflow.steps.first
    rs = run.run_steps.create!(step: step, status: "running", attempt: 1, position: 1, started_at: 1.hour.ago)
    run.update_columns(updated_at: 90.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
    rs.update_columns(updated_at: 90.minutes.ago)  # rubocop:disable Rails/SkipsModelValidations

    summary = MegaUpdate.call(io: @io, dry_run: true, stale_minutes: 30)

    assert_not summary.aborted
    assert_equal 0, summary.hung_runs_failed,
                 "dry_run shouldn't actually flip statuses"
    assert_equal "running", run.reload.status
    assert_equal "running", rs.reload.status
    assert_includes @io.string, "DRY RUN"
    assert_includes @io.string, "(would fail)"
  end

  # Regression: `git -C <path> <cmd>` walks UP the directory tree when <path>
  # isn't itself a git repo. If a project's local_path is just a plain dir
  # nested inside another git repo (e.g. seneschal's own working tree during
  # tests), git would operate on the PARENT repo by mistake — silently
  # switching branches in the developer's own checkout. prepare_projects
  # must require .git/ at the exact local_path.
  test "prepare_projects skips projects whose local_path is not itself a git repo" do
    Project.find_each do |p|
      # Each fixture project's local_path may or may not exist; ensure it
      # exists as a plain dir but is NOT a git repo (no .git/).
      FileUtils.mkdir_p(p.local_path) if p.repo_status == "ready"
      FileUtils.rm_rf(File.join(p.local_path, ".git")) if File.directory?(File.join(p.local_path, ".git"))
    end

    summary = MegaUpdate.call(io: @io)

    assert_not summary.aborted
    assert_equal 0, summary.projects_prepared, "should have skipped all non-git project paths"
    assert_includes @io.string, "no .git at"
  end

  test "Summary struct exposes the documented counters" do
    summary = MegaUpdate.call(io: @io)
    assert_respond_to summary, :aborted
    assert_respond_to summary, :hung_runs_failed
    assert_respond_to summary, :orphan_run_steps_failed
    assert_respond_to summary, :legacy_steps_converted
    assert_respond_to summary, :legacy_steps_skipped
    assert_respond_to summary, :projects_prepared
    assert_respond_to summary, :errors
  end

  # The pre-worktree-era `git checkout main && git pull` workflow steps
  # now fail inside the per-run worktree because the canonical clone
  # already has the default branch checked out. mega_update rewrites
  # them as documented no-ops so historical RunStep records keep their
  # step labels and future runs succeed.
  test "converts legacy `git checkout main` Step bodies into documented no-ops" do
    workflow = workflows(:deploy)
    step = workflow.steps.create!(
      name: "Pull Latest Main", step_type: "command",
      body: "git checkout main && git pull",
      position: 999, timeout: 30, max_retries: 0, config: {}
    )

    summary = MegaUpdate.call(io: @io)
    assert_not summary.aborted
    assert_equal 1, summary.legacy_steps_converted

    step.reload
    assert_includes step.name, "legacy no-op"
    assert step.body.start_with?(MegaUpdate::CONVERTED_MARKER)
    assert_includes step.body, "git checkout main && git pull", "original body preserved as comment"
    assert step.body.lines.last.strip == "true", "ends with `true` so bash exits 0"
  end

  test "converts `git checkout master` and `git checkout trunk` variants" do
    workflow = workflows(:deploy)
    master = workflow.steps.create!(
      name: "Pull master", step_type: "command", body: "git checkout master && git pull --ff-only",
      position: 990, timeout: 30, max_retries: 0, config: {}
    )
    trunk = workflow.steps.create!(
      name: "Switch trunk", step_type: "command", body: "git checkout trunk",
      position: 991, timeout: 30, max_retries: 0, config: {}
    )

    summary = MegaUpdate.call(io: @io)
    assert_equal 2, summary.legacy_steps_converted
    assert master.reload.body.start_with?(MegaUpdate::CONVERTED_MARKER)
    assert trunk.reload.body.start_with?(MegaUpdate::CONVERTED_MARKER)
  end

  test "skips Step bodies that wrap `git checkout main` inside larger scripts" do
    workflow = workflows(:deploy)
    complex = workflow.steps.create!(
      name: "Complex deploy", step_type: "script",
      body: "set -e\ngit checkout main\nbundle install\nrails db:migrate",
      position: 989, timeout: 30, max_retries: 0, config: {}
    )

    summary = MegaUpdate.call(io: @io)
    assert_equal 0, summary.legacy_steps_converted
    assert_equal "set -e\ngit checkout main\nbundle install\nrails db:migrate", complex.reload.body
  end

  test "is idempotent — already-converted steps are skipped" do
    workflow = workflows(:deploy)
    step = workflow.steps.create!(
      name: "Pull Latest Main", step_type: "command",
      body: "git checkout main && git pull",
      position: 988, timeout: 30, max_retries: 0, config: {}
    )

    MegaUpdate.call(io: StringIO.new)
    second = MegaUpdate.call(io: @io)

    assert_equal 0, second.legacy_steps_converted, "second run finds nothing to convert"
    assert_equal 1, second.legacy_steps_skipped, "second run sees the already-converted step"
    assert step.reload.body.start_with?(MegaUpdate::CONVERTED_MARKER)
  end

  test "dry_run reports legacy-step conversions without changing them" do
    workflow = workflows(:deploy)
    step = workflow.steps.create!(
      name: "Pull Latest Main", step_type: "command",
      body: "git checkout main && git pull",
      position: 987, timeout: 30, max_retries: 0, config: {}
    )
    original_body = step.body

    summary = MegaUpdate.call(io: @io, dry_run: true, stale_minutes: 30)
    assert_equal 0, summary.legacy_steps_converted
    assert_equal original_body, step.reload.body
    assert_includes @io.string, "(would convert)"
  end
end
