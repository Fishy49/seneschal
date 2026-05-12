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
    assert_equal ["global"], kinds
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
