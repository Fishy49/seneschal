require "test_helper"
require "tmpdir"

class SkillMdWriterTest < ActiveSupport::TestCase
  # Every test writes into a temp directory. Nothing here may touch the repo.
  setup do
    @dir = Dir.mktmpdir("seneschal-skill-writer")
    @project = Project.create!(name: "Writer Project", repo_url: "git@example.com:acme/x.git", local_path: @dir)
    @skill_dir = File.join(@dir, ".seneschal", "skills", "reviewer")
    FileUtils.mkdir_p(@skill_dir)
    File.write(File.join(@skill_dir, "SKILL.md"), <<~MD)
      ---
      name: reviewer
      description: Reviews things
      ---

      Original body.
    MD
    @skill = Skill.create!(name: "reviewer", project: @project,
                           source_kind: "project_seneschal", relative_path: "reviewer")
    @skill.refresh_cached_metadata!
  end

  teardown { FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir) }

  test "writes the edited file back and the next run reads the new body" do
    edited = "---\nname: reviewer\ndescription: Reviews things carefully\n---\n\nRewritten body.\n"
    result = SkillMdWriter.call(skill: @skill, content: edited)

    assert result.ok, result.error
    assert_equal edited, File.read(File.join(@skill_dir, "SKILL.md"))
    assert_includes Skill.find(@skill.id).body, "Rewritten body."
  end

  test "saving refreshes the cached description and content hash" do
    before = @skill.content_hash
    SkillMdWriter.call(skill: @skill, content: "---\nname: reviewer\ndescription: Now different\n---\n\nBody.\n")

    @skill.reload
    assert_equal "Now different", @skill.description
    assert_not_equal before, @skill.content_hash
  end

  test "refuses a rename, because that would move the folder too" do
    result = SkillMdWriter.call(skill: @skill, content: "---\nname: something-else\n---\n\nBody.\n")

    assert_not result.ok
    assert_match(/Renaming/, result.error)
    assert_includes File.read(File.join(@skill_dir, "SKILL.md")), "Original body."
  end

  test "allows a file with no frontmatter name" do
    assert SkillMdWriter.call(skill: @skill, content: "Just a body.\n").ok
  end

  test "refuses to touch a skill synced from a repo" do
    repo = SkillRepo.create!(name: "acme-skills", repo_url: "git@example.com:acme/skills.git",
                             local_path: @dir, priority: 1)
    synced = Skill.create!(name: "from-repo", skill_repo: repo, source_kind: "skill_repo",
                           relative_path: "reviewer")

    result = SkillMdWriter.call(skill: synced, content: "anything")

    assert_not result.ok
    assert_match(/acme-skills/, result.error)
    assert_includes File.read(File.join(@skill_dir, "SKILL.md")), "Original body."
  end
end
