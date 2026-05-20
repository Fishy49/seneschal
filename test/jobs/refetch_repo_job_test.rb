require "test_helper"
require "tmpdir"
require "fileutils"
require "open3"

class RefetchRepoJobTest < ActiveJob::TestCase
  setup do
    @project = projects(:seneschal)
    @tmpdir = Dir.mktmpdir("seneschal-refetch-test-")
    @origin_path = File.join(@tmpdir, "origin.git")
    @clone_path = File.join(@tmpdir, "clone")

    # Bare "remote" with one initial commit on main.
    in_dir(@tmpdir, "git", "init", "-q", "--bare", "-b", "main", @origin_path)

    seed_path = File.join(@tmpdir, "seed")
    FileUtils.mkdir_p(seed_path)
    in_dir(seed_path, "git", "init", "-q", "-b", "main")
    in_dir(seed_path, "git", "config", "user.email", "test@example.com")
    in_dir(seed_path, "git", "config", "user.name", "Test")
    File.write(File.join(seed_path, "README.md"), "hello")
    in_dir(seed_path, "git", "add", "README.md")
    in_dir(seed_path, "git", "commit", "-q", "-m", "init")
    in_dir(seed_path, "git", "remote", "add", "origin", @origin_path)
    in_dir(seed_path, "git", "push", "-q", "origin", "main")

    # Local clone the job will refresh.
    in_dir(@tmpdir, "git", "clone", "-q", @origin_path, @clone_path)
    in_dir(@clone_path, "git", "config", "user.email", "test@example.com")
    in_dir(@clone_path, "git", "config", "user.name", "Test")

    @project.update!(local_path: @clone_path, repo_status: "ready")
  end

  teardown do
    FileUtils.rm_rf(@tmpdir) if @tmpdir
  end

  test "advances local main to origin's tip when HEAD is on default branch" do
    add_remote_commit("hello.txt", "world")
    before = local_main_sha

    RefetchRepoJob.new.perform(@project)

    assert_equal "ready", @project.reload.repo_status
    assert_not_equal before, local_main_sha
    assert_equal origin_main_sha, local_main_sha
    assert File.exist?(File.join(@clone_path, "hello.txt"))
  end

  test "updates the default branch ref without disturbing HEAD when checked out elsewhere" do
    in_dir(@clone_path, "git", "checkout", "-q", "-b", "feature/x")
    add_remote_commit("hello.txt", "world")

    RefetchRepoJob.new.perform(@project)

    assert_equal "ready", @project.reload.repo_status
    # HEAD stayed on the feature branch; main moved to origin/main.
    head, = in_dir(@clone_path, "git", "symbolic-ref", "--short", "HEAD")
    assert_equal "feature/x", head.strip
    assert_equal origin_main_sha, local_main_sha
  end

  test "marks project errored when fetch fails" do
    # Point origin at a path that doesn't exist so `git fetch` blows up.
    in_dir(@clone_path, "git", "remote", "set-url", "origin", File.join(@tmpdir, "missing.git"))

    RefetchRepoJob.new.perform(@project)

    assert_equal "error", @project.reload.repo_status
  end

  test "no-ops when project is not ready" do
    @project.update!(repo_status: "not_cloned")
    RefetchRepoJob.new.perform(@project)
    assert_equal "not_cloned", @project.reload.repo_status
  end

  private

  def in_dir(dir, *cmd)
    Open3.capture3(*cmd, chdir: dir)
  end

  def add_remote_commit(filename, contents)
    work = Dir.mktmpdir("seneschal-refetch-push-")
    in_dir(@tmpdir, "git", "clone", "-q", @origin_path, work)
    in_dir(work, "git", "config", "user.email", "test@example.com")
    in_dir(work, "git", "config", "user.name", "Test")
    File.write(File.join(work, filename), contents)
    in_dir(work, "git", "add", filename)
    in_dir(work, "git", "commit", "-q", "-m", "add #{filename}")
    in_dir(work, "git", "push", "-q", "origin", "main")
  ensure
    FileUtils.rm_rf(work) if work
  end

  def local_main_sha
    stdout, = in_dir(@clone_path, "git", "rev-parse", "refs/heads/main")
    stdout.strip
  end

  def origin_main_sha
    stdout, = in_dir(@clone_path, "git", "rev-parse", "refs/remotes/origin/main")
    stdout.strip
  end
end
