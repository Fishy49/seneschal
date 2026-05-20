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

  test "GET index renders shared and project sections" do
    get skills_path
    assert_response :success
    assert_match "Shared", response.body
    assert_match "ingest_feature", response.body
    assert_match "deploy_check", response.body
  end

  test "GET show displays skill" do
    get skill_path(skills(:shared_skill))
    assert_response :success
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
    @scaffolded_project_dirs << File.join(project.local_path, ".seneschal", "skills", "proj-new")

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

  test "PATCH update succeeds with scope-only params" do
    patch skill_path(skills(:shared_skill)), params: {
      skill: { scope: "" }
    }
    assert_redirected_to skill_path(skills(:shared_skill))
  end

  test "PATCH update reassigns from project to shared" do
    patch skill_path(skills(:project_skill)), params: {
      skill: { scope: "" }
    }
    assert_redirected_to skill_path(skills(:project_skill))
  end

  test "PATCH update updates default_output_variable" do
    skill = skills(:project_skill)
    patch skill_path(skill), params: {
      skill: { default_output_variable: "feature_plan" }
    }
    assert_redirected_to skill_path(skill)
    assert_equal "feature_plan", skill.reload.default_output_variable
  end

  test "DELETE destroy" do
    skill = Skill.create!(name: "disposable", source_kind: "global", relative_path: "disposable")
    assert_difference "Skill.count", -1 do
      delete skill_path(skill)
    end
    assert_redirected_to skills_path
  end

  # --- POST import_reference_schema ---

  test "import_reference_schema creates a JsonSchema and sets it as the skill's default" do # rubocop:disable Metrics/BlockLength
    skill_dir = File.join(@tmp_global_root, "schema-haver")
    FileUtils.mkdir_p(File.join(skill_dir, "references"))
    File.write(File.join(skill_dir, "SKILL.md"), "---\nname: schema-haver\ndescription: x\n---\n\nbody\n")
    File.write(File.join(skill_dir, "references", "feature_plan.schema.json"), <<~JSON)
      {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "Feature Plan",
        "description": "A plan, but typed.",
        "type": "object",
        "required": ["headline"],
        "properties": {
          "headline": { "type": "string" }
        }
      }
    JSON
    skill = Skill.create!(name: "schema-haver", source_kind: "global", relative_path: "schema-haver")
    skill.refresh_cached_metadata!

    assert_difference "JsonSchema.count", 1 do
      post import_reference_schema_skill_path(skill, reference: "feature_plan.schema.json")
    end
    assert_redirected_to skill_path(skill)

    new_schema = JsonSchema.find_by(name: "schema-haver__feature_plan")
    assert_not_nil new_schema
    parsed = JSON.parse(new_schema.body)
    assert_equal "Feature Plan", parsed["title"]
    assert_not parsed.key?("$schema"), "$schema must be stripped to keep the CLI happy"

    skill.reload
    assert_equal new_schema.id, skill.default_json_schema_id
    assert_equal "feature_plan", skill.default_output_variable
  end

  test "import_reference_schema is idempotent — re-importing overwrites in place" do
    skill_dir = File.join(@tmp_global_root, "idem-skill")
    FileUtils.mkdir_p(File.join(skill_dir, "references"))
    File.write(File.join(skill_dir, "SKILL.md"), "---\nname: idem-skill\ndescription: x\n---\n\nbody\n")
    ref = File.join(skill_dir, "references", "out.schema.json")
    File.write(ref, '{"type":"object","properties":{"a":{"type":"string"}},"required":["a"]}')
    skill = Skill.create!(name: "idem-skill", source_kind: "global", relative_path: "idem-skill")
    skill.refresh_cached_metadata!

    post import_reference_schema_skill_path(skill, reference: "out.schema.json")
    File.write(ref, '{"type":"object","properties":{"b":{"type":"string"}},"required":["b"]}')

    assert_no_difference "JsonSchema.count" do
      post import_reference_schema_skill_path(skill, reference: "out.schema.json")
    end
    new_body = JSON.parse(JsonSchema.find_by(name: "idem-skill__out").body)
    assert new_body["properties"].key?("b"), "second import should update the body in place"
  end

  test "import_reference_schema rejects missing reference files" do
    skill = skills(:shared_skill)
    post import_reference_schema_skill_path(skill, reference: "does_not_exist.json")
    assert_redirected_to skill_path(skill)
    assert_match(/not found/i, flash[:alert])
  end

  test "import_reference_schema rejects malformed JSON" do
    skill_dir = File.join(@tmp_global_root, "bad-json")
    FileUtils.mkdir_p(File.join(skill_dir, "references"))
    File.write(File.join(skill_dir, "SKILL.md"), "---\nname: bad-json\ndescription: x\n---\n\nbody\n")
    File.write(File.join(skill_dir, "references", "broken.json"), "not even json")
    skill = Skill.create!(name: "bad-json", source_kind: "global", relative_path: "bad-json")
    skill.refresh_cached_metadata!

    assert_no_difference "JsonSchema.count" do
      post import_reference_schema_skill_path(skill, reference: "broken.json")
    end
    assert_redirected_to skill_path(skill)
    assert_match(/not valid JSON/i, flash[:alert])
  end
end
