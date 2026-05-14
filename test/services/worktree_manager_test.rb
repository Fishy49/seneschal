require "test_helper"
require "tmpdir"
require "fileutils"
require "open3"

class WorktreeManagerTest < ActiveSupport::TestCase
  setup do
    @project = projects(:seneschal)
    @tmpdir = Dir.mktmpdir("seneschal-worktree-test-")
    @repo_path = File.join(@tmpdir, "repo")
    @worktree_root = File.join(@tmpdir, "worktrees")

    FileUtils.mkdir_p(@repo_path)
    in_repo("git", "init", "-q", "-b", "main")
    in_repo("git", "config", "user.email", "test@example.com")
    in_repo("git", "config", "user.name", "Test")
    File.write(File.join(@repo_path, "README.md"), "hi")
    in_repo("git", "add", "README.md")
    in_repo("git", "commit", "-q", "-m", "init")

    @project.update!(local_path: @repo_path, repo_status: "ready")
    Setting["worktree_root"] = @worktree_root
    @workflow = workflows(:deploy)
    @workflow.update!(project: @project)
  end

  teardown do
    Setting.find_by(key: "worktree_root")&.destroy
    Setting.find_by(key: "worktree_retention_days")&.destroy
    FileUtils.rm_rf(@tmpdir) if @tmpdir
  end

  test "allocate creates a worktree on a seneschal/run-<id> branch" do
    run = create_run
    path = WorktreeManager.allocate(run)

    assert_equal File.join(@worktree_root, run.id.to_s), path
    assert File.directory?(path), "worktree dir should exist"
    assert File.exist?(File.join(path, "README.md")), "worktree should contain repo files"

    branches, _stderr, status = Open3.capture3("git", "-C", @repo_path, "branch", "--list")
    assert status.success?
    assert_includes branches, "seneschal/run-#{run.id}"

    run.reload
    assert_equal path, run.worktree_path
    assert_not run.worktree_retained?
  end

  test "allocate raises WorktreeError when project is not ready" do
    @project.update_column(:repo_status, "not_cloned") # rubocop:disable Rails/SkipsModelValidations
    run = create_run
    assert_raises(WorktreeManager::WorktreeError) { WorktreeManager.allocate(run) }
  end

  test "ensure_for reuses an existing worktree" do
    run = create_run
    first = WorktreeManager.allocate(run)
    second = WorktreeManager.ensure_for(run)
    assert_equal first, second
    assert File.directory?(second)
  end

  test "ensure_for reallocates when worktree_path no longer exists on disk" do
    run = create_run
    WorktreeManager.allocate(run)
    FileUtils.rm_rf(run.worktree_path)
    # Prune the stale metadata; otherwise git refuses to recreate the branch
    Open3.capture3("git", "-C", @repo_path, "worktree", "prune")
    Open3.capture3("git", "-C", @repo_path, "branch", "-D", "seneschal/run-#{run.id}")

    new_path = WorktreeManager.ensure_for(run)
    assert File.directory?(new_path)
  end

  test "ensure_for clears worktree_retained when reusing" do
    run = create_run
    WorktreeManager.allocate(run)
    WorktreeManager.retain(run)
    assert run.reload.worktree_retained?

    WorktreeManager.ensure_for(run)
    assert_not run.reload.worktree_retained?
  end

  test "cleanup removes the worktree, branch, and clears the path" do
    run = create_run
    path = WorktreeManager.allocate(run)
    assert File.directory?(path)

    WorktreeManager.cleanup(run)

    assert_not File.directory?(path), "worktree dir should be gone"
    branches, _err, _status = Open3.capture3("git", "-C", @repo_path, "branch", "--list")
    assert_not_includes branches, "seneschal/run-#{run.id}"

    run.reload
    assert_nil run.worktree_path
    assert_not run.worktree_retained?
  end

  test "cleanup is a no-op when no worktree_path is set" do
    run = create_run
    assert_nothing_raised { WorktreeManager.cleanup(run) }
  end

  # Regression: when the worktree directory is removed out-of-band (rm_rf'd by
  # the operator, disk failure, etc.), `git worktree remove` fails. cleanup
  # falls back to rm_rf and must then `worktree prune` BEFORE attempting
  # `branch -D`, otherwise git still believes the branch is checked out in
  # the (now-gone) worktree and refuses to delete it.
  test "cleanup deletes the branch even after the worktree dir was removed externally" do
    run = create_run
    WorktreeManager.allocate(run)

    # Simulate out-of-band removal: directory is gone, git metadata is stale.
    FileUtils.rm_rf(run.worktree_path)

    WorktreeManager.cleanup(run)

    branches, _err, _status = Open3.capture3("git", "-C", @repo_path, "branch", "--list")
    assert_not_includes branches, "seneschal/run-#{run.id}",
                        "branch should be deleted even when the worktree dir was removed out of band"
  end

  test "retain flips the retention flag without touching the worktree" do
    run = create_run
    path = WorktreeManager.allocate(run)
    WorktreeManager.retain(run)
    assert run.reload.worktree_retained?
    assert File.directory?(path)
  end

  test "reap_stale removes retained worktrees past the retention window" do
    fresh = create_run
    stale = create_run

    WorktreeManager.allocate(fresh)
    WorktreeManager.retain(fresh)
    fresh.update_columns(finished_at: 1.day.ago, updated_at: 1.day.ago) # rubocop:disable Rails/SkipsModelValidations

    stale_path = WorktreeManager.allocate(stale)
    WorktreeManager.retain(stale)
    stale.update_columns(finished_at: 30.days.ago, updated_at: 30.days.ago) # rubocop:disable Rails/SkipsModelValidations

    WorktreeManager.reap_stale(older_than: 7.days)

    assert File.directory?(fresh.reload.worktree_path), "recent retained worktree should survive"
    assert_not File.directory?(stale_path), "old retained worktree should be reaped"
    assert_nil stale.reload.worktree_path
  end

  test "reap_stale skips non-retained worktrees regardless of age" do
    run = create_run
    path = WorktreeManager.allocate(run)
    run.update_columns(finished_at: 30.days.ago, updated_at: 30.days.ago) # rubocop:disable Rails/SkipsModelValidations

    WorktreeManager.reap_stale(older_than: 7.days)

    assert File.directory?(path), "non-retained worktrees are never reaped"
  end

  test "worktree_root respects Setting override" do
    Setting["worktree_root"] = "/tmp/custom-worktrees"
    assert_equal "/tmp/custom-worktrees", WorktreeManager.worktree_root
  end

  test "retention_days respects Setting override" do
    Setting["worktree_retention_days"] = "14"
    assert_equal 14, WorktreeManager.retention_days
  end

  test "retention_days falls back to DEFAULT_RETENTION_DAYS when unset" do
    Setting.find_by(key: "worktree_retention_days")&.destroy
    assert_equal WorktreeManager::DEFAULT_RETENTION_DAYS, WorktreeManager.retention_days
  end

  test "allocate branches off origin/HEAD even when local_path is on a feature branch" do
    # Build a fake remote so origin/HEAD is set, then check the clone out on a
    # feature branch with bogus content. The worktree should contain main's
    # content, not the feature branch's.
    remote = File.join(@tmpdir, "remote.git")
    in_dir(@tmpdir, "git", "init", "--bare", "-q", "-b", "main", remote)

    clone = File.join(@tmpdir, "clone")
    in_dir(@tmpdir, "git", "clone", "-q", remote, clone)
    in_dir(clone, "git", "config", "user.email", "test@example.com")
    in_dir(clone, "git", "config", "user.name", "Test")
    File.write(File.join(clone, "MAIN.md"), "main content")
    in_dir(clone, "git", "add", "MAIN.md")
    in_dir(clone, "git", "commit", "-q", "-m", "main commit")
    in_dir(clone, "git", "push", "-q", "origin", "main")
    # remote now has main; clone is at main HEAD; origin/HEAD points at origin/main

    # Switch clone to a feature branch with extra junk content
    in_dir(clone, "git", "checkout", "-q", "-b", "feature/junk")
    File.write(File.join(clone, "JUNK.md"), "junk content")
    in_dir(clone, "git", "add", "JUNK.md")
    in_dir(clone, "git", "commit", "-q", "-m", "junk")

    @project.update!(local_path: clone)
    run = create_run
    path = WorktreeManager.allocate(run)

    assert File.exist?(File.join(path, "MAIN.md")), "worktree should contain main content"
    assert_not File.exist?(File.join(path, "JUNK.md")), "worktree should NOT contain feature-branch content"
  end

  test "detect_start_point falls back to HEAD when there is no remote" do
    # The setup repo has no remote configured; origin/HEAD isn't set and
    # origin/main / origin/master don't resolve either.
    assert_equal "HEAD", WorktreeManager.detect_start_point(@project)
  end

  test "default_branch_name returns the bare branch name when origin/HEAD is set" do
    remote = File.join(@tmpdir, "remote.git")
    in_dir(@tmpdir, "git", "init", "--bare", "-q", "-b", "main", remote)
    seed = File.join(@tmpdir, "seed-default-branch")
    in_dir(@tmpdir, "git", "clone", "-q", remote, seed)
    in_dir(seed, "git", "config", "user.email", "test@example.com")
    in_dir(seed, "git", "config", "user.name", "Test")
    File.write(File.join(seed, "README.md"), "hi")
    in_dir(seed, "git", "add", "README.md")
    in_dir(seed, "git", "commit", "-q", "-m", "init")
    in_dir(seed, "git", "push", "-q", "origin", "main")

    clone = File.join(@tmpdir, "clone-default-branch")
    in_dir(@tmpdir, "git", "clone", "-q", remote, clone)
    @project.update!(local_path: clone)

    assert_equal "main", WorktreeManager.default_branch_name(@project)
  end

  test "default_branch_name returns nil when no remote info is available" do
    assert_nil WorktreeManager.default_branch_name(@project)
  end

  test "detect_start_point returns origin/main when the remote ref exists" do
    remote = File.join(@tmpdir, "remote.git")
    in_dir(@tmpdir, "git", "init", "--bare", "-q", "-b", "main", remote)

    # Seed the remote with a commit so a subsequent clone gets origin refs
    seed = File.join(@tmpdir, "seed")
    in_dir(@tmpdir, "git", "clone", "-q", remote, seed)
    in_dir(seed, "git", "config", "user.email", "test@example.com")
    in_dir(seed, "git", "config", "user.name", "Test")
    File.write(File.join(seed, "README.md"), "hi")
    in_dir(seed, "git", "add", "README.md")
    in_dir(seed, "git", "commit", "-q", "-m", "init")
    in_dir(seed, "git", "push", "-q", "origin", "main")

    clone = File.join(@tmpdir, "clone-for-detect")
    in_dir(@tmpdir, "git", "clone", "-q", remote, clone)
    @project.update!(local_path: clone)

    assert_equal "origin/main", WorktreeManager.detect_start_point(@project)
  end

  private

  def in_dir(dir, *cmd)
    _, _, status = Open3.capture3(*cmd, chdir: dir)
    raise "git command failed in #{dir}: #{cmd.inspect}" unless status.success?
  end

  def create_run
    @workflow.runs.create!(status: "pending", context: {}, input: {})
  end

  def in_repo(*cmd)
    _, _, status = Open3.capture3(*cmd, chdir: @repo_path)
    raise "git command failed: #{cmd.inspect}" unless status.success?
  end
end
