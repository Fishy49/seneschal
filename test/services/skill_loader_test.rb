require "test_helper"
require "tmpdir"
require "fileutils"
require "securerandom"

class SkillLoaderTest < ActiveSupport::TestCase
  setup do
    @project = projects(:seneschal)
    @tmpdir = Dir.mktmpdir("seneschal-skillloader-")
    @project.update!(local_path: @tmpdir, repo_status: "ready")
    @global_dirs = []
  end

  teardown do
    FileUtils.rm_rf(@tmpdir) if @tmpdir
    @global_dirs.each { |d| FileUtils.rm_rf(d) }
  end

  test "resolves from project .claude/skills first" do
    name = unique_name
    write_skill_md(File.join(@tmpdir, ".claude/skills/#{name}"), name)
    write_global_skill_md(name)

    resolved = SkillLoader.resolve(name, project: @project)
    assert_equal "project", resolved.source_kind
    assert_equal File.join(@tmpdir, ".claude/skills/#{name}"), resolved.absolute_path
  end

  test "resolves from project .seneschal/skills when .claude/skills is empty" do
    name = unique_name
    write_skill_md(File.join(@tmpdir, ".seneschal/skills/#{name}"), name)

    resolved = SkillLoader.resolve(name, project: @project)
    assert_equal "project_seneschal", resolved.source_kind
  end

  test "falls back to global skills root when project has nothing" do
    name = unique_name
    global = write_global_skill_md(name)

    resolved = SkillLoader.resolve(name, project: @project)
    assert_equal "global", resolved.source_kind
    assert_equal global, resolved.absolute_path
  end

  test "returns nil when the skill doesn't exist anywhere" do
    assert_nil SkillLoader.resolve(unique_name, project: @project)
  end

  test "skips project tiers when no project is given" do
    name = unique_name
    write_global_skill_md(name)

    resolved = SkillLoader.resolve(name, project: nil)
    assert_equal "global", resolved.source_kind
  end

  test "candidates enumerates all locations regardless of presence" do
    paths = SkillLoader.new("anything", project: @project).candidates
    kinds = paths.map(&:first)
    assert_equal ["project", "project_seneschal", "global"], kinds
  end

  test "candidates omits project tiers when project is nil" do
    paths = SkillLoader.new("anything", project: nil).candidates
    kinds = paths.map(&:first)
    assert_includes kinds, "global"
    assert_not_includes kinds, "project"
    assert_not_includes kinds, "project_seneschal"
  end

  test "multiple skills_global_roots are walked in priority order" do
    root_a = Dir.mktmpdir("loader-multi-a-")
    root_b = Dir.mktmpdir("loader-multi-b-")
    Setting["skills_global_roots"] = "#{root_a}\n#{root_b}"

    name = unique_name
    write_skill_md(File.join(root_b, name), name)

    resolved = SkillLoader.resolve(name, project: @project)
    assert_equal "global", resolved.source_kind
    assert_equal File.join(root_b, name), resolved.absolute_path
  ensure
    FileUtils.rm_rf(root_a) if root_a
    FileUtils.rm_rf(root_b) if root_b
    Setting.find_by(key: "skills_global_roots")&.destroy
  end

  test "skills_global_roots first-match wins when the same skill exists in multiple roots" do
    root_a = Dir.mktmpdir("loader-pri-a-")
    root_b = Dir.mktmpdir("loader-pri-b-")
    Setting["skills_global_roots"] = "#{root_a}\n#{root_b}"

    name = unique_name
    write_skill_md(File.join(root_a, name), name)
    write_skill_md(File.join(root_b, name), name)

    resolved = SkillLoader.resolve(name, project: @project)
    assert_equal File.join(root_a, name), resolved.absolute_path
  ensure
    FileUtils.rm_rf(root_a) if root_a
    FileUtils.rm_rf(root_b) if root_b
    Setting.find_by(key: "skills_global_roots")&.destroy
  end

  test "enabled SkillRepos are walked after global roots, in priority order" do
    repo_root = Dir.mktmpdir("loader-repo-root-")
    Setting["skill_repo_root"] = repo_root

    repo_dir = File.join(repo_root, "test-pack-#{SecureRandom.hex(3)}")
    FileUtils.mkdir_p(repo_dir)

    name = unique_name
    write_skill_md(File.join(repo_dir, name), name)

    repo = SkillRepo.create!(name: "loader-test-#{SecureRandom.hex(3)}",
                             repo_url: "https://example.com/x.git",
                             local_path: repo_dir, priority: 50)

    resolved = SkillLoader.resolve(name, project: @project)
    assert_equal "skill_repo", resolved.source_kind
    assert_equal File.join(repo_dir, name), resolved.absolute_path

    repo.destroy
  ensure
    FileUtils.rm_rf(repo_root) if repo_root
    Setting.find_by(key: "skill_repo_root")&.destroy
  end

  test "disabled SkillRepos are not in candidates" do
    repo_root = Dir.mktmpdir("loader-disabled-")
    Setting["skill_repo_root"] = repo_root
    repo = SkillRepo.create!(name: "disabled-#{SecureRandom.hex(3)}",
                             repo_url: "https://example.com/x.git",
                             local_path: File.join(repo_root, "x"),
                             enabled: false)

    kinds = SkillLoader.new("any", project: @project).candidates.map(&:first)
    assert_not_includes kinds, "skill_repo"
    repo.destroy
  ensure
    FileUtils.rm_rf(repo_root) if repo_root
    Setting.find_by(key: "skill_repo_root")&.destroy
  end

  private

  # Filesystem is shared across parallel test workers; per-test unique names
  # prevent one worker's teardown from clobbering another worker's fixtures.
  def unique_name
    "_loader_test_#{SecureRandom.hex(4)}"
  end

  def write_skill_md(dir, name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "SKILL.md"), <<~MD)
      ---
      name: #{name}
      description: A test skill named #{name}
      ---
      Body for #{name}.
    MD
    dir
  end

  def write_global_skill_md(name)
    dir = File.join(SkillLoader.global_root, name)
    @global_dirs << dir
    write_skill_md(dir, name)
  end
end
