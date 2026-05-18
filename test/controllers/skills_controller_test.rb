require "test_helper"

class SkillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
    @tmp_global_root = Dir.mktmpdir
    Setting["skills_global_roots"] = @tmp_global_root
    @scaffolded_project_dirs = []
  end

  teardown do
    FileUtils.remove_entry(@tmp_global_root) if @tmp_global_root && File.directory?(@tmp_global_root)
    Setting.where(key: "skills_global_roots").delete_all
    @scaffolded_project_dirs.each { |d| FileUtils.rm_rf(d) }
  end

  test "GET index lists skills" do
    get skills_path
    assert_response :success
  end

  test "GET index displays group section with group name and skill" do
    get skills_path
    assert_response :success
    assert_match "Frontend", response.body
    assert_match "lint_check", response.body
  end

  test "GET index filters by group_id" do
    get skills_path, params: { group_id: project_groups(:frontend).id }
    assert_response :success
    assert_match skills(:group_skill).name, response.body
    assert_no_match skills(:shared_skill).name, response.body
  end

  test "GET show displays skill" do
    get skill_path(skills(:shared_skill))
    assert_response :success
  end

  test "GET show displays group designation for group skill" do
    get skill_path(skills(:group_skill))
    assert_response :success
    assert_match "Group: Frontend", response.body
  end

  test "GET show surfaces on-disk path, frontmatter, scripts/, and references/ for filesystem-backed skills" do
    skill_dir = File.join(@tmp_global_root, "rich-skill")
    FileUtils.mkdir_p(File.join(skill_dir, "scripts"))
    FileUtils.mkdir_p(File.join(skill_dir, "references"))
    File.write(File.join(skill_dir, "SKILL.md"), <<~MD)
      ---
      name: rich-skill
      description: Demonstrates aux files
      allowed-tools: Read, Grep, Glob
      ---

      # Rich Skill
    MD
    File.write(File.join(skill_dir, "scripts", "do_thing.sh"), "#!/bin/bash\necho hello\n")
    File.write(File.join(skill_dir, "references", "patterns.md"), "## Pattern\n\nExample.\n")

    skill = Skill.create!(name: "rich-skill", source_kind: "global", relative_path: "rich-skill")
    skill.refresh_cached_metadata!

    get skill_path(skill)
    assert_response :success
    assert_match skill_dir, response.body
    assert_match "Frontmatter", response.body
    assert_match "allowed-tools", response.body
    assert_match "Read, Grep, Glob", response.body
    assert_match "scripts/", response.body
    assert_match "do_thing.sh", response.body
    assert_match "references/", response.body
    assert_match "patterns.md", response.body
  end

  test "GET new renders form" do
    get new_skill_path
    assert_response :success
  end

  test "POST create shared skill scaffolds SKILL.md under global root" do
    assert_difference "Skill.count", 1 do
      post skills_path, params: {
        skill: { name: "new-skill", body: "Do the thing", description: "A skill" }
      }
    end
    skill = Skill.last
    assert_redirected_to skill_path(skill)
    assert_nil skill.project_id
    assert_equal "global", skill.source_kind
    assert_equal "new-skill", skill.relative_path
    assert File.exist?(File.join(@tmp_global_root, "new-skill", "SKILL.md"))
  end

  test "POST create project skill scaffolds under <project>/.seneschal/skills/<name>/" do
    project = projects(:seneschal)
    @scaffolded_project_dirs << File.join(project.local_path, ".seneschal")

    assert_difference "Skill.count", 1 do
      post skills_path, params: {
        skill: { name: "proj-new", body: "Do the thing", description: "Project-only",
                 scope: "project:#{project.id}" }
      }
    end
    skill = Skill.last
    assert_redirected_to skill_path(skill)
    assert_equal project.id, skill.project_id
    assert_equal "project_seneschal", skill.source_kind
    assert File.exist?(File.join(project.local_path, ".seneschal", "skills", "proj-new", "SKILL.md"))
  end

  test "POST create rejects group scope (no disk projection)" do
    assert_no_difference "Skill.count" do
      post skills_path, params: {
        skill: { name: "group-skill", body: "x", description: "y",
                 scope: "group:#{project_groups(:frontend).id}" }
      }
    end
    assert_response :unprocessable_content
    assert_match(/group/i, response.body)
  end

  test "POST create rejects non-kebab name" do
    assert_no_difference "Skill.count" do
      post skills_path, params: {
        skill: { name: "Bad Name", body: "x", description: "y" }
      }
    end
    assert_response :unprocessable_content
  end

  test "POST create rejects blank description" do
    assert_no_difference "Skill.count" do
      post skills_path, params: { skill: { name: "bare", body: "" } }
    end
    assert_response :unprocessable_content
  end

  test "POST create with conflicting on-disk SKILL.md surfaces an error" do
    FileUtils.mkdir_p(File.join(@tmp_global_root, "already-there"))
    File.write(File.join(@tmp_global_root, "already-there", "SKILL.md"), "---\nname: already-there\ndescription: x\n---\n")

    assert_no_difference "Skill.count" do
      post skills_path, params: {
        skill: { name: "already-there", description: "Trying again", body: "x" }
      }
    end
    assert_response :unprocessable_content
    assert_match(/already exists/i, response.body)
  end

  test "GET edit renders form" do
    get edit_skill_path(skills(:shared_skill))
    assert_response :success
  end

  test "GET edit pre-selects group scope" do
    get edit_skill_path(skills(:group_skill))
    assert_response :success
    assert_select "option[selected][value=?]", "group:#{project_groups(:frontend).id}"
  end

  test "PATCH update succeeds with scope-only params" do
    patch skill_path(skills(:shared_skill)), params: {
      skill: { scope: "" }
    }
    assert_redirected_to skill_path(skills(:shared_skill))
  end

  test "PATCH update reassigns from project to group" do
    patch skill_path(skills(:project_skill)), params: {
      skill: { scope: "group:#{project_groups(:frontend).id}" }
    }
    assert_redirected_to skill_path(skills(:project_skill))
    skill = skills(:project_skill).reload
    assert_nil skill.project_id
    assert_equal project_groups(:frontend).id, skill.project_group_id
  end

  test "PATCH update reassigns from group to shared" do
    patch skill_path(skills(:group_skill)), params: {
      skill: { scope: "" }
    }
    skill = skills(:group_skill).reload
    assert_nil skill.project_id
    assert_nil skill.project_group_id
    assert skill.shared?
  end

  test "PATCH update updates default_output_variable" do
    skill = skills(:group_skill)
    patch skill_path(skill), params: {
      skill: { default_output_variable: "feature_plan" }
    }
    assert_redirected_to skill_path(skill)
    assert_equal "feature_plan", skill.reload.default_output_variable
  end

  test "DELETE destroy" do
    skill = Skill.create!(name: "disposable", body: "temp")
    assert_difference "Skill.count", -1 do
      delete skill_path(skill)
    end
    assert_redirected_to skills_path
  end
end
