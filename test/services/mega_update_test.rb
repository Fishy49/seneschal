require "test_helper"
require "stringio"
require "tmpdir"
require "fileutils"
require "securerandom"

class MegaUpdateTest < ActiveSupport::TestCase
  setup do
    @io = StringIO.new
    @global_root = Dir.mktmpdir("seneschal-mega-update-skills-")
    Setting["skills_global_root"] = @global_root

    # Fresh slate — fixtures may include active runs; clear them
    RunStep.where(status: "running").destroy_all
    Run.where(status: ["running", "pending", "awaiting_approval"]).destroy_all
  end

  teardown do
    FileUtils.rm_rf(@global_root) if @global_root
    Setting.find_by(key: "skills_global_root")&.destroy
  end

  test "aborts when a pending run exists" do
    workflow = workflows(:deploy)
    workflow.runs.create!(status: "pending", context: {}, input: {})

    summary = MegaUpdate.call(io: @io, skip_skill_export: true)

    assert summary.aborted
    assert_includes @io.string, "ABORT"
    assert_includes @io.string, "pending"
  end

  test "aborts when an awaiting_approval run exists" do
    workflow = workflows(:deploy)
    workflow.runs.create!(status: "awaiting_approval", context: {}, input: {})

    summary = MegaUpdate.call(io: @io, skip_skill_export: true)
    assert summary.aborted
  end

  test "aborts when a fresh running run exists (recent heartbeat)" do
    workflow = workflows(:deploy)
    run = workflow.runs.create!(status: "running", context: {}, input: {})
    run.update_columns(updated_at: 2.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

    summary = MegaUpdate.call(io: @io, skip_skill_export: true, stale_minutes: 30)
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

    summary = MegaUpdate.call(io: @io, skip_skill_export: true, stale_minutes: 30)

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

    summary = MegaUpdate.call(io: @io, skip_skill_export: true)

    assert_equal 1, summary.orphan_run_steps_failed
    assert_equal "failed", rs.reload.status
  end

  test "exports DB-backed skills to the configured global root" do
    Skill.where(skill_repo_id: nil).destroy_all
    Skill.create!(name: "test-export-#{SecureRandom.hex(3)}",
                  description: "Test skill",
                  body: "Test body")

    summary = MegaUpdate.call(io: @io)

    assert_equal 1, summary.skills_exported
    assert Dir.children(@global_root).any?
  end

  test "dry_run reports actions without changing state" do
    workflow = workflows(:deploy)
    run = workflow.runs.create!(status: "running", context: {}, input: {})
    step = workflow.steps.first
    rs = run.run_steps.create!(step: step, status: "running", attempt: 1, position: 1, started_at: 1.hour.ago)
    run.update_columns(updated_at: 90.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
    rs.update_columns(updated_at: 90.minutes.ago)  # rubocop:disable Rails/SkipsModelValidations

    summary = MegaUpdate.call(io: @io, dry_run: true, skip_skill_export: true, stale_minutes: 30)

    assert_not summary.aborted
    assert_equal 0, summary.hung_runs_failed,
                 "dry_run shouldn't actually flip statuses"
    assert_equal "running", run.reload.status
    assert_equal "running", rs.reload.status
    assert_includes @io.string, "DRY RUN"
    assert_includes @io.string, "(would fail)"
  end

  test "skip_skill_export keeps skills untouched" do
    Skill.where(skill_repo_id: nil).destroy_all
    Skill.create!(name: "leave-alone-#{SecureRandom.hex(3)}", body: "x")

    summary = MegaUpdate.call(io: @io, skip_skill_export: true)

    assert_equal 0, summary.skills_exported
    assert_empty Dir.children(@global_root)
  end

  test "is idempotent — second run reports nothing to do" do
    Skill.where(skill_repo_id: nil).destroy_all
    skill = Skill.create!(name: "idem-#{SecureRandom.hex(3)}", body: "x")

    MegaUpdate.call(io: StringIO.new)
    second = MegaUpdate.call(io: @io)

    assert_not second.aborted
    assert_equal 0, second.hung_runs_failed
    assert_equal 0, second.orphan_run_steps_failed
    assert_equal 0, second.skills_exported # already on disk
    assert_equal 1, second.skills_skipped # detected as already-exported
    skill.reload
    assert skill.filesystem_backed?
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

    summary = MegaUpdate.call(io: @io, skip_skill_export: true)

    assert_not summary.aborted
    assert_equal 0, summary.projects_prepared, "should have skipped all non-git project paths"
    assert_includes @io.string, "no .git at"
  end

  test "Summary struct exposes the documented counters" do
    summary = MegaUpdate.call(io: @io, skip_skill_export: true)
    assert_respond_to summary, :aborted
    assert_respond_to summary, :hung_runs_failed
    assert_respond_to summary, :orphan_run_steps_failed
    assert_respond_to summary, :projects_prepared
    assert_respond_to summary, :skills_exported
    assert_respond_to summary, :skills_skipped
    assert_respond_to summary, :errors
  end
end
