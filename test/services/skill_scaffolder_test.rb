require "test_helper"

class SkillScaffolderTest < ActiveSupport::TestCase
  setup do
    @tmp_root = Dir.mktmpdir
    Setting["skills_global_roots"] = @tmp_root
  end

  teardown do
    FileUtils.remove_entry(@tmp_root) if File.directory?(@tmp_root)
    Setting.where(key: "skills_global_roots").delete_all
  end

  test "scaffolds a shared skill under the global root" do
    result = SkillScaffolder.call(name: "my-skill", description: "Does the thing")

    assert_equal "global", result.source_kind
    assert_equal "my-skill", result.relative_path
    assert_equal File.join(@tmp_root, "my-skill"), result.absolute_path
    assert_not result.already_existed
    assert File.exist?(result.skill_md_path)

    parsed = SkillMdParser.parse(File.read(result.skill_md_path))
    assert_equal "my-skill", parsed.frontmatter["name"]
    assert_equal "Does the thing", parsed.frontmatter["description"]
    assert_includes parsed.body, "Author the skill's procedural body"
  end

  test "writes provided body verbatim when given" do
    body = "# Title\n\nUse this skill to do things.\n"
    result = SkillScaffolder.call(name: "with-body", description: "Has a body", body: body)

    parsed = SkillMdParser.parse(File.read(result.skill_md_path))
    assert_includes parsed.body, "# Title"
    assert_includes parsed.body, "Use this skill to do things."
  end

  test "scaffolds a project skill under <local_path>/.seneschal/skills/<name>/" do
    Dir.mktmpdir do |project_root|
      project = Project.new(name: "Repo", repo_url: "https://example/r.git", local_path: project_root)
      project.save!(validate: false)

      result = SkillScaffolder.call(name: "fix-thing", description: "Fixes the thing", project: project)

      assert_equal "project_seneschal", result.source_kind
      assert_equal "fix-thing", result.relative_path
      expected_dir = File.join(project_root, ".seneschal", "skills", "fix-thing")
      assert_equal expected_dir, result.absolute_path
      assert File.exist?(File.join(expected_dir, "SKILL.md"))
    end
  end

  test "returns already_existed when SKILL.md is present without overwriting" do
    dir = File.join(@tmp_root, "preexisting")
    FileUtils.mkdir_p(dir)
    original_content = "---\nname: preexisting\ndescription: original\n---\n\nHand-written body.\n"
    File.write(File.join(dir, "SKILL.md"), original_content)

    result = SkillScaffolder.call(name: "preexisting", description: "would-overwrite")

    assert result.already_existed
    assert_equal original_content, File.read(result.skill_md_path)
  end

  test "rejects blank name" do
    err = assert_raises(SkillScaffolder::Error) do
      SkillScaffolder.call(name: "", description: "x")
    end
    assert_match(/name is required/i, err.message)
  end

  test "rejects non-kebab-case name" do
    err = assert_raises(SkillScaffolder::Error) do
      SkillScaffolder.call(name: "Bad Name", description: "x")
    end
    assert_match(/kebab-case/i, err.message)
  end

  test "rejects blank description (frontmatter schema requires it)" do
    err = assert_raises(SkillScaffolder::Error) do
      SkillScaffolder.call(name: "no-desc", description: "")
    end
    assert_match(/frontmatter/i, err.message)
  end

  test "rejects project_group scope" do
    group = ProjectGroup.create!(name: "G")
    err = assert_raises(SkillScaffolder::Error) do
      SkillScaffolder.call(name: "g-skill", description: "x", project_group: group)
    end
    assert_match(/group/i, err.message)
  end

  test "rollback removes the scaffolded SKILL.md and its enclosing directory" do
    result = SkillScaffolder.call(name: "ephemeral", description: "x")
    assert File.file?(result.skill_md_path)
    assert File.directory?(result.absolute_path)

    assert SkillScaffolder.rollback(result)
    assert_not File.exist?(result.skill_md_path)
    assert_not File.exist?(result.absolute_path)
  end

  test "rollback refuses to touch paths outside known skill roots" do
    fake_result = SkillScaffolder::Result.new(
      source_kind: "global",
      relative_path: "x",
      absolute_path: "/tmp/totally-elsewhere/x",
      skill_md_path: "/tmp/totally-elsewhere/x/SKILL.md",
      already_existed: false
    )
    FileUtils.mkdir_p("/tmp/totally-elsewhere/x")
    File.write("/tmp/totally-elsewhere/x/SKILL.md", "not ours")

    assert_not SkillScaffolder.rollback(fake_result)
    assert File.exist?("/tmp/totally-elsewhere/x/SKILL.md"), "Rollback must not delete files outside known skill roots"
  ensure
    FileUtils.rm_rf("/tmp/totally-elsewhere")
  end

  test "rollback leaves the directory intact when it still contains other files" do
    result = SkillScaffolder.call(name: "shared-dir", description: "x")
    File.write(File.join(result.absolute_path, "extra.md"), "kept")

    SkillScaffolder.rollback(result)

    assert_not File.exist?(result.skill_md_path)
    assert File.directory?(result.absolute_path)
    assert File.exist?(File.join(result.absolute_path, "extra.md"))
  end

  test "quotes descriptions containing YAML-significant characters" do
    result = SkillScaffolder.call(name: "tricky", description: "Use when: needs colons & quotes")
    parsed = SkillMdParser.parse(File.read(result.skill_md_path))
    assert_equal "Use when: needs colons & quotes", parsed.frontmatter["description"]
  end
end
