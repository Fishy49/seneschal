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

  test "imports skills written under .seneschal/skills too" do
    Dir.mktmpdir do |dir|
      project = Project.new(name: "SeneschalDirTest", repo_url: "https://github.com/t/s.git", local_path: dir)
      project.save!(validate: false)

      skill_dir = File.join(dir, ".seneschal", "skills", "scaffolded")
      FileUtils.mkdir_p(skill_dir)
      File.write(File.join(skill_dir, "SKILL.md"), "---\nname: scaffolded\ndescription: Made here\n---\n\nBody.\n")

      result = SkillImporter.new(project).call

      assert_equal ["scaffolded"], result[:imported]
      imported = Skill.find_by(project: project, name: "scaffolded")
      assert_equal "project_seneschal", imported.source_kind
      assert_includes imported.body, "Body."
    end
  end

  test "imports from both skill directories in one pass" do
    Dir.mktmpdir do |dir|
      project = Project.new(name: "BothDirsTest", repo_url: "https://github.com/t/b.git", local_path: dir)
      project.save!(validate: false)

      [".claude", ".seneschal"].each_with_index do |_, index|
        base = index.zero? ? ".claude" : ".seneschal"
        skill_dir = File.join(dir, base, "skills", "from-#{base.delete(".")}")
        FileUtils.mkdir_p(skill_dir)
        File.write(File.join(skill_dir, "SKILL.md"), "---\nname: from-#{base.delete(".")}\n---\n\nBody.\n")
      end

      result = SkillImporter.new(project).call

      assert_equal ["from-claude", "from-seneschal"], result[:imported].sort
    end
  end
end
