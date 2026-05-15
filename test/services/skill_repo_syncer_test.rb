require "test_helper"
require "tmpdir"
require "fileutils"
require "open3"
require "securerandom"

class SkillRepoSyncerTest < ActiveSupport::TestCase
  setup do
    @sandbox = Dir.mktmpdir("seneschal-skillrepo-sync-")
    @repo_root = File.join(@sandbox, "skill_repos")
    @remote = File.join(@sandbox, "remote.git")
    @seed = File.join(@sandbox, "seed")

    Setting["skill_repo_root"] = @repo_root

    init_bare_remote
    seed_remote_with_skill("alpha", description: "Alpha skill", body: "Alpha body")
  end

  teardown do
    FileUtils.rm_rf(@sandbox) if @sandbox
    Setting.find_by(key: "skill_repo_root")&.destroy
  end

  test "first sync clones the repo and indexes every */SKILL.md as a Skill record" do
    repo = SkillRepo.create!(name: "test-pack-#{SecureRandom.hex(3)}", repo_url: @remote)
    result = SkillRepoSyncer.new(repo).call

    assert_equal :ok, result.status
    assert_includes result.imported, "alpha"
    assert File.directory?(File.join(repo.local_path, ".git"))

    skill = Skill.find_by(skill_repo_id: repo.id, name: "alpha")
    assert_not_nil skill
    assert_equal "skill_repo", skill.source_kind
    assert_equal "alpha", skill.relative_path
    assert_equal "Alpha skill", skill.description
    assert_equal "Alpha skill", skill.cached_metadata["description"]
    assert skill.filesystem_backed?
    assert_includes skill.body, "Alpha body"
  end

  test "subsequent sync pulls updates and adds newly added skills" do
    repo = SkillRepo.create!(name: "test-pack-#{SecureRandom.hex(3)}", repo_url: @remote)
    SkillRepoSyncer.new(repo).call

    seed_remote_with_skill("beta", description: "Beta", body: "Beta body")
    result = SkillRepoSyncer.new(repo).call

    assert_equal :ok, result.status
    assert_includes result.imported, "alpha"
    assert_includes result.imported, "beta"
    assert Skill.exists?(skill_repo_id: repo.id, name: "beta")
  end

  test "skills removed from the remote get archived, not deleted" do
    repo = SkillRepo.create!(name: "test-pack-#{SecureRandom.hex(3)}", repo_url: @remote)
    seed_remote_with_skill("doomed", description: "Will vanish", body: "x")
    SkillRepoSyncer.new(repo).call

    doomed = Skill.find_by(skill_repo_id: repo.id, name: "doomed")
    assert_not doomed.archived?

    remove_skill_from_remote("doomed")
    result = SkillRepoSyncer.new(repo).call

    assert_includes result.archived, "doomed"
    doomed.reload
    assert doomed.archived?
    assert_not_nil doomed.archived_at
  end

  test "re-adding an archived skill un-archives it" do
    repo = SkillRepo.create!(name: "test-pack-#{SecureRandom.hex(3)}", repo_url: @remote)
    seed_remote_with_skill("comeback", description: "Will return", body: "x")
    SkillRepoSyncer.new(repo).call

    remove_skill_from_remote("comeback")
    SkillRepoSyncer.new(repo).call
    assert Skill.find_by(skill_repo_id: repo.id, name: "comeback").archived?

    seed_remote_with_skill("comeback", description: "Returned", body: "x")
    SkillRepoSyncer.new(repo).call

    skill = Skill.find_by(skill_repo_id: repo.id, name: "comeback")
    assert_not skill.archived?
    assert_equal "Returned", skill.description
  end

  test "captures per-skill .install-notes for SkillRepo#install_notes" do
    add_install_notes_to_remote("alpha", "Set ALPHA_API_KEY before using this skill.")
    repo = SkillRepo.create!(name: "test-pack-#{SecureRandom.hex(3)}", repo_url: @remote)
    SkillRepoSyncer.new(repo).call

    repo.reload
    assert_equal "Set ALPHA_API_KEY before using this skill.", repo.install_notes_for("alpha")
  end

  test "install_notes are truncated past the configured byte cap" do
    oversize = "x" * (SkillRepoSyncer::MAX_INSTALL_NOTES_BYTES + 5_000)
    add_install_notes_to_remote("alpha", oversize)
    repo = SkillRepo.create!(name: "test-pack-#{SecureRandom.hex(3)}", repo_url: @remote)
    SkillRepoSyncer.new(repo).call

    captured = repo.reload.install_notes_for("alpha")
    assert captured.bytesize < oversize.bytesize, "expected truncation"
    assert_includes captured, "truncated"
  end

  test "logs a warning when an imported SKILL.md has invalid frontmatter" do
    # SKILL.md is missing the required `description` field. The syncer
    # still imports the skill (with a nil description) but should log.
    seed_remote_with_invalid_skill("missingdesc")
    repo = SkillRepo.create!(name: "test-pack-#{SecureRandom.hex(3)}", repo_url: @remote)

    captured = capture_rails_log do
      result = SkillRepoSyncer.new(repo).call
      assert_equal :ok, result.status
      assert_includes result.imported, "missingdesc"
    end

    assert_match(/invalid SKILL\.md frontmatter/i, captured)
    assert_match(/missingdesc/, captured)
  end

  test "sync error is captured on the SkillRepo and returns :error status" do
    repo = SkillRepo.create!(
      name: "test-pack-#{SecureRandom.hex(3)}",
      repo_url: File.join(@sandbox, "does-not-exist.git")
    )
    result = SkillRepoSyncer.new(repo).call

    assert_equal :error, result.status
    repo.reload
    assert repo.last_sync_error.present?
    assert_nil repo.last_synced_at
  end

  private

  def init_bare_remote
    _, _, status = Open3.capture3("git", "init", "--bare", "-q", "-b", "main", @remote)
    raise "bare init failed" unless status.success?

    _, _, clone_status = Open3.capture3("git", "clone", "-q", @remote, @seed)
    raise "seed clone failed" unless clone_status.success?

    git_in(@seed, "config", "user.email", "test@example.com")
    git_in(@seed, "config", "user.name", "Test")
  end

  def seed_remote_with_skill(name, description:, body:)
    dir = File.join(@seed, name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "SKILL.md"), <<~MD)
      ---
      name: #{name}
      description: #{description}
      ---
      #{body}
    MD
    git_in(@seed, "add", ".")
    git_in(@seed, "commit", "-q", "--allow-empty", "-m", "add #{name}")
    git_in(@seed, "push", "-q", "origin", "main")
  end

  def remove_skill_from_remote(name)
    FileUtils.rm_rf(File.join(@seed, name))
    git_in(@seed, "add", "-A")
    git_in(@seed, "commit", "-q", "-m", "remove #{name}")
    git_in(@seed, "push", "-q", "origin", "main")
  end

  def add_install_notes_to_remote(skill_name, content)
    dir = File.join(@seed, skill_name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, ".install-notes"), content)
    git_in(@seed, "add", ".")
    git_in(@seed, "commit", "-q", "-m", "install notes for #{skill_name}")
    git_in(@seed, "push", "-q", "origin", "main")
  end

  # Seeds a SKILL.md with frontmatter that's missing the required
  # `description` field — enough to fail JSON-schema validation but still
  # parse cleanly so the syncer's import path runs.
  def seed_remote_with_invalid_skill(name)
    dir = File.join(@seed, name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "SKILL.md"), <<~MD)
      ---
      name: #{name}
      ---
      body
    MD
    git_in(@seed, "add", ".")
    git_in(@seed, "commit", "-q", "-m", "add #{name} (invalid)")
    git_in(@seed, "push", "-q", "origin", "main")
  end

  def capture_rails_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end

  def git_in(dir, *args)
    _, stderr, status = Open3.capture3("git", "-C", dir, *args)
    raise "git #{args.first} failed in #{dir}: #{stderr.strip}" unless status.success?
  end
end
