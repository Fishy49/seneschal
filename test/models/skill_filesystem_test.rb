require "test_helper"
require "tmpdir"
require "fileutils"

class SkillFilesystemTest < ActiveSupport::TestCase
  setup do
    @project = projects(:seneschal)
    @tmpdir = Dir.mktmpdir("seneschal-skill-fs-")
    @project.update!(local_path: @tmpdir, repo_status: "ready")
  end

  teardown do
    FileUtils.rm_rf(@tmpdir) if @tmpdir
  end

  test "legacy DB-backed skill is not filesystem_backed" do
    skill = Skill.create!(name: "legacy_skill", body: "do a thing")
    assert_not skill.filesystem_backed?
    assert_nil skill.absolute_path
    assert_equal "do a thing", skill.body
  end

  test "filesystem-backed skill reads body from disk" do
    dir = File.join(@tmpdir, ".claude/skills/disk_skill")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "SKILL.md"), <<~MD)
      ---
      name: disk_skill
      description: Lives on disk
      ---
      The actual prompt content.
    MD

    skill = Skill.new(name: "disk_skill", project: @project,
                      source_kind: "project", relative_path: "disk_skill")
    assert skill.filesystem_backed?
    assert_equal dir, skill.absolute_path
    assert_equal "The actual prompt content.\n", skill.body
  end

  test "validation skips body presence when filesystem-backed" do
    skill = Skill.new(name: "no_body_required", project: @project,
                      source_kind: "project", relative_path: "anything")
    assert skill.valid?, skill.errors.full_messages.inspect
  end

  test "validation requires body for legacy DB-backed skills" do
    skill = Skill.new(name: "needs_body")
    assert_not skill.valid?
    assert_includes skill.errors[:body], "can't be blank"
  end

  test "source_kind must be one of the recognized values when set" do
    skill = Skill.new(name: "bogus_kind", project: @project,
                      source_kind: "made_up", relative_path: "x")
    assert_not skill.valid?
    assert skill.errors[:source_kind].any?
  end

  test "absolute_path returns nil for project-scoped when project has no local_path" do
    proj = Project.create!(name: "no-path", repo_url: "https://example.com/x", local_path: @tmpdir)
    # Force local_path blank for the test
    proj.update_columns(local_path: "") # rubocop:disable Rails/SkipsModelValidations
    skill = Skill.new(name: "x", project: proj, source_kind: "project", relative_path: "x")
    assert_nil skill.absolute_path
  end

  test "absolute_path uses .seneschal/skills/ for project_seneschal" do
    skill = Skill.new(name: "x", project: @project,
                      source_kind: "project_seneschal", relative_path: "x")
    assert_equal File.join(@tmpdir, ".seneschal/skills/x"), skill.absolute_path
  end

  test "absolute_path uses Rails.root/skills/ for global" do
    skill = Skill.new(name: "x", source_kind: "global", relative_path: "x")
    assert_equal File.join(SkillLoader.global_root, "x"), skill.absolute_path
  end

  test "refresh_cached_metadata! stores frontmatter and content hash" do
    dir = File.join(@tmpdir, ".claude/skills/cached_skill")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "SKILL.md"), <<~MD)
      ---
      name: cached_skill
      description: cached description
      allowed-tools: Read,Edit
      ---
      Body.
    MD

    skill = Skill.create!(name: "cached_skill", project: @project,
                          source_kind: "project", relative_path: "cached_skill")
    assert skill.refresh_cached_metadata!

    skill.reload
    assert_equal "cached description", skill.cached_metadata["description"]
    assert_equal "Read,Edit", skill.cached_metadata["allowed-tools"]
    assert skill.content_hash.match?(/\A[a-f0-9]{64}\z/)
  end

  test "refresh_cached_metadata! returns false for legacy skills" do
    skill = Skill.create!(name: "legacy", body: "x")
    assert_not skill.refresh_cached_metadata!
  end

  test "scripts_dir and references_dir compute paths under absolute_path" do
    skill = Skill.new(name: "x", project: @project,
                      source_kind: "project", relative_path: "x")
    assert_equal File.join(@tmpdir, ".claude/skills/x/scripts"), skill.scripts_dir
    assert_equal File.join(@tmpdir, ".claude/skills/x/references"), skill.references_dir
  end

  test "body falls back to the DB column when filesystem-backed file is missing" do
    skill = Skill.new(name: "ghost", project: @project, body: "fallback body",
                      source_kind: "project", relative_path: "ghost")
    assert skill.filesystem_backed?
    assert_nil skill.parsed_skill_md
    assert_equal "fallback body", skill.body
  end

  test "parsed_skill_md is memoized — disk reads happen at most once per instance" do
    dir = File.join(@tmpdir, ".claude/skills/memo")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "SKILL.md"), "---\nname: memo\ndescription: m\n---\nv1\n")

    skill = Skill.new(name: "memo", project: @project,
                      source_kind: "project", relative_path: "memo")

    first = skill.body
    File.write(File.join(dir, "SKILL.md"), "---\nname: memo\ndescription: m\n---\nv2\n")
    second = skill.body
    assert_equal first, second, "expected memoization to hide the on-disk edit"
    assert_equal "v1\n", first
  end
end
