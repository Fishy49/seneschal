require "test_helper"

class SkillImporterTest < ActiveSupport::TestCase
  setup do
    @project = projects(:seneschal)
  end

  test "returns nil when no .claude/skills directory" do
    Dir.mktmpdir do |empty_root|
      project = Project.new(name: "Empty", repo_url: "https://github.com/t/e.git", local_path: empty_root)
      project.save!(validate: false)
      result = SkillImporter.new(project).call
      assert_nil result
    end
  end

  test "imports skills from SKILL.md files" do
    Dir.mktmpdir do |dir|
      project = Project.new(name: "ImportTest", repo_url: "https://github.com/t/t.git", local_path: dir)
      project.save!(validate: false)

      skill_dir = File.join(dir, ".claude", "skills", "my-skill")
      FileUtils.mkdir_p(skill_dir)
      File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
        ---
        name: my-skill
        description: A test skill
        ---

        # My Skill

        Do the thing.
      MD

      result = SkillImporter.new(project).call
      assert_equal ["my-skill"], result[:imported]
      assert_empty result[:skipped]

      skill = project.skills.find_by(name: "my-skill")
      assert_not_nil skill
      assert_equal "project", skill.source_kind
      assert_equal "my-skill", skill.relative_path
      assert_equal "A test skill", skill.description
      assert_includes skill.body, "# My Skill"
    end
  end

  test "skips skills that already exist" do
    Dir.mktmpdir do |dir|
      project = Project.new(name: "SkipTest", repo_url: "https://github.com/t/t.git", local_path: dir)
      project.save!(validate: false)
      project.skills.create!(name: "existing", source_kind: "project", relative_path: "existing")

      skill_dir = File.join(dir, ".claude", "skills", "existing")
      FileUtils.mkdir_p(skill_dir)
      File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
        ---
        name: existing
        description: Updated
        ---

        New body.
      MD

      result = SkillImporter.new(project).call
      assert_empty result[:imported]
      assert_equal ["existing"], result[:skipped]
    end
  end

  test "uses directory name when frontmatter has no name" do
    Dir.mktmpdir do |dir|
      project = Project.new(name: "DirNameTest", repo_url: "https://github.com/t/t.git", local_path: dir)
      project.save!(validate: false)

      skill_dir = File.join(dir, ".claude", "skills", "fallback-name")
      FileUtils.mkdir_p(skill_dir)
      File.write(File.join(skill_dir, "SKILL.md"), "Just a prompt with no frontmatter.")

      result = SkillImporter.new(project).call
      assert_equal ["fallback-name"], result[:imported]
    end
  end
end
