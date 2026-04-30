require "test_helper"

class SkillImporterTest < ActiveSupport::TestCase
  setup do
    @project = projects(:seneschal)
    @skills_dir = File.join(@project.local_path, ".claude", "skills")
  end

  test "returns nil when no .claude/skills directory" do
    result = SkillImporter.new(@project).call
    assert_nil result
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
      assert_equal "A test skill", skill.description
      assert_includes skill.body, "# My Skill"
    end
  end

  test "skips skills that already exist" do
    Dir.mktmpdir do |dir|
      project = Project.new(name: "SkipTest", repo_url: "https://github.com/t/t.git", local_path: dir)
      project.save!(validate: false)
      project.skills.create!(name: "existing", body: "old body")

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
      assert_equal "old body", project.skills.find_by(name: "existing").body
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

  test "imports skills under a project group when target is a ProjectGroup" do
    Dir.mktmpdir do |dir|
      project = Project.new(name: "GroupImportTest", repo_url: "https://github.com/t/t.git", local_path: dir)
      project.save!(validate: false)
      group = ProjectGroup.create!(name: "ImportGroup")

      skill_dir = File.join(dir, ".claude", "skills", "foo")
      FileUtils.mkdir_p(skill_dir)
      File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
        ---
        name: foo
        description: A group skill
        ---

        Do foo things.
      MD

      result = SkillImporter.new(project, target: group).call
      assert_equal ["foo"], result[:imported]
      assert_empty result[:skipped]

      skill = Skill.find_by(name: "foo")
      assert_not_nil skill
      assert_equal group.id, skill.project_group_id
      assert_nil skill.project_id
      assert_empty project.skills
    end
  end
end
