require "test_helper"
require "tmpdir"
require "fileutils"
require "securerandom"

class SkillExporterTest < ActiveSupport::TestCase
  setup do
    @global_root = Dir.mktmpdir("seneschal-skills-global-")
    Setting["skills_global_root"] = @global_root

    @project = projects(:seneschal)
    @project_path = Dir.mktmpdir("seneschal-skills-project-")
    @project.update!(local_path: @project_path, repo_status: "ready")
  end

  teardown do
    FileUtils.rm_rf(@global_root) if @global_root
    FileUtils.rm_rf(@project_path) if @project_path
    Setting.find_by(key: "skills_global_root")&.destroy
  end

  test "shared skill exports to <global_root>/<slug>/SKILL.md" do
    skill = skills(:shared_skill) # ingest_feature, no project
    skill.update!(body: "Do the ingest thing for ${task_title}")

    result = SkillExporter.call(skill)
    assert_equal :exported, result.status
    expected_path = File.join(@global_root, "ingest-feature", "SKILL.md")
    assert_equal expected_path, result.path
    assert File.exist?(expected_path)

    skill.reload
    assert_equal "global", skill.source_kind
    assert_equal "ingest-feature", skill.relative_path
    assert skill.filesystem_backed?
  end

  test "project-scoped skill exports to <project>/.seneschal/skills/<slug>/" do
    skill = skills(:project_skill) # deploy_check, project: seneschal
    result = SkillExporter.call(skill)
    assert_equal :exported, result.status
    expected_path = File.join(@project_path, ".seneschal", "skills", "deploy-check", "SKILL.md")
    assert_equal expected_path, result.path

    skill.reload
    assert_equal "project_seneschal", skill.source_kind
    assert_equal "deploy-check", skill.relative_path
  end

  test "group-scoped skill is skipped" do
    skill = skills(:group_skill) # lint_check, project_group: frontend
    result = SkillExporter.call(skill)
    assert_equal :skipped_group, result.status
    assert_nil result.path
    skill.reload
    assert_not skill.filesystem_backed?
  end

  test "frontmatter includes name and description in the rendered SKILL.md" do
    skill = Skill.create!(
      name: unique_skill_name("plan"),
      description: "Plan a feature from a task",
      body: "Body content here."
    )

    SkillExporter.call(skill)
    parsed = SkillMdParser.parse(File.read(skill.skill_md_path))

    assert_equal skill.relative_path, parsed.frontmatter["name"]
    assert_equal "Plan a feature from a task", parsed.frontmatter["description"]
    assert_includes parsed.body, "Body content here."
  end

  test "frontmatter generates a TODO description when the source description is blank" do
    skill = Skill.create!(name: unique_skill_name("nodesc"), description: "", body: "x")
    SkillExporter.call(skill)
    parsed = SkillMdParser.parse(File.read(skill.skill_md_path))
    assert_match(/\(TODO\)/, parsed.frontmatter["description"])
  end

  test "allowed-tools is inferred from the most common Step config" do
    skill = Skill.create!(name: unique_skill_name("withsteps"), body: "x")
    workflow = workflows(:deploy)
    workflow.steps.create!(
      name: "uses_read_glob", step_type: "skill", skill: skill, position: 50,
      timeout: 30, max_retries: 0, config: { "allowed_tools" => "Read,Glob" }
    )
    workflow.steps.create!(
      name: "uses_read_glob_again", step_type: "skill", skill: skill, position: 51,
      timeout: 30, max_retries: 0, config: { "allowed_tools" => "Read,Glob" }
    )
    workflow.steps.create!(
      name: "uses_bash", step_type: "skill", skill: skill, position: 52,
      timeout: 30, max_retries: 0, config: { "allowed_tools" => "Bash" }
    )

    SkillExporter.call(skill)
    parsed = SkillMdParser.parse(File.read(skill.skill_md_path))
    assert_equal "Read,Glob", parsed.frontmatter["allowed-tools"]
  end

  test "allowed-tools is omitted when no Step overrides it" do
    skill = Skill.create!(name: unique_skill_name("defaulttools"), body: "x")
    SkillExporter.call(skill)
    parsed = SkillMdParser.parse(File.read(skill.skill_md_path))
    assert_not parsed.frontmatter.key?("allowed-tools")
  end

  test "exporting again is idempotent and does not overwrite operator edits" do
    skill = Skill.create!(name: unique_skill_name("edited"), description: "v1", body: "v1 body")
    SkillExporter.call(skill)

    # Operator edits the SKILL.md by hand
    File.write(skill.skill_md_path, <<~MD)
      ---
      name: edited
      description: hand-edited
      ---
      Operator's improved body.
    MD

    result = SkillExporter.call(skill)
    assert_equal :skipped, result.status

    on_disk = File.read(skill.skill_md_path)
    assert_includes on_disk, "Operator's improved body"
    assert_includes on_disk, "hand-edited"
  end

  test "Skill#body reads from disk after export" do
    skill = Skill.create!(name: unique_skill_name("fromdisk"), description: "d", body: "original DB body")
    SkillExporter.call(skill)
    skill.reload
    assert_equal "original DB body", skill.body.strip
  end

  test "names that are already kebab-case stay kebab-case" do
    skill = Skill.create!(name: "already-kebab-#{SecureRandom.hex(3)}", body: "x")
    result = SkillExporter.call(skill)
    assert skill.reload.relative_path.start_with?("already-kebab")
    assert_includes result.path, "/already-kebab"
  end

  test "name with only special characters falls back to skill-<id>" do
    skill = Skill.new(name: "_", body: "x")
    skill.save(validate: false)
    SkillExporter.call(skill)
    assert_equal "skill-#{skill.id}", skill.reload.relative_path
  end

  private

  def unique_skill_name(prefix)
    "#{prefix}_#{SecureRandom.hex(4)}"
  end
end
