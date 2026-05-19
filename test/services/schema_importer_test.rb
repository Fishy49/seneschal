require "test_helper"

class SchemaImporterTest < ActiveSupport::TestCase
  setup do
    @tmp = Dir.mktmpdir("schema-importer-")
    Setting["skills_global_roots"] = @tmp
    @skill_dir = File.join(@tmp, "sample")
    FileUtils.mkdir_p(File.join(@skill_dir, "references"))
    File.write(File.join(@skill_dir, "SKILL.md"), "---\nname: sample\ndescription: x\n---\n\nbody\n")
    @skill = Skill.create!(name: "sample", source_kind: "global", relative_path: "sample")
  end

  teardown do
    FileUtils.rm_rf(@tmp)
    Setting.where(key: "skills_global_roots").delete_all
  end

  def write_ref(name, body)
    File.write(File.join(@skill_dir, "references", name), body)
  end

  test "imports the file as a JsonSchema row keyed by <skill>__<basename>" do
    write_ref("feature_plan.schema.json", '{"type":"object","properties":{"a":{"type":"string"}}}')

    result = SchemaImporter.call(skill: @skill, reference: "feature_plan.schema.json")

    assert_equal :imported, result.status
    assert_equal "sample__feature_plan", result.schema.name
    assert_equal "sample__feature_plan", JsonSchema.last.name
  end

  test "strips $schema before persisting" do
    write_ref("with_schema.json", <<~JSON)
      {"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"a":{"type":"string"}}}
    JSON
    result = SchemaImporter.call(skill: @skill, reference: "with_schema.json")
    assert_not JSON.parse(result.schema.body).key?("$schema")
  end

  test "set_default: :always overwrites an existing default" do
    other = JsonSchema.create!(name: "other", body: '{"type":"object"}')
    @skill.update!(default_json_schema_id: other.id, default_output_variable: "other")
    write_ref("new.json", '{"type":"object","properties":{"a":{"type":"string"}}}')

    SchemaImporter.call(skill: @skill, reference: "new.json", set_default: :always)
    @skill.reload
    assert_equal "sample__new", @skill.default_json_schema.name
  end

  test "set_default: :if_blank leaves an existing default alone" do
    other = JsonSchema.create!(name: "other", body: '{"type":"object"}')
    @skill.update!(default_json_schema_id: other.id, default_output_variable: "other")
    write_ref("new.json", '{"type":"object","properties":{"a":{"type":"string"}}}')

    SchemaImporter.call(skill: @skill, reference: "new.json", set_default: :if_blank)
    @skill.reload
    assert_equal "other", @skill.default_json_schema.name
    # …but the JsonSchema row is still created so the operator can pick it later.
    assert JsonSchema.exists?(name: "sample__new")
  end

  test "set_default: :if_blank wires the default when the skill has none" do
    write_ref("new.json", '{"type":"object","properties":{"a":{"type":"string"}}}')

    SchemaImporter.call(skill: @skill, reference: "new.json", set_default: :if_blank)
    @skill.reload
    assert_equal "sample__new", @skill.default_json_schema.name
    assert_equal "new", @skill.default_output_variable
  end

  test "set_default: :never imports without touching the skill" do
    write_ref("new.json", '{"type":"object","properties":{"a":{"type":"string"}}}')

    SchemaImporter.call(skill: @skill, reference: "new.json", set_default: :never)
    @skill.reload
    assert_nil @skill.default_json_schema_id
    assert JsonSchema.exists?(name: "sample__new")
  end

  test "re-importing updates the body in place (idempotent on schema name)" do
    write_ref("evolve.json", '{"type":"object","properties":{"v1":{"type":"string"}},"required":["v1"]}')
    SchemaImporter.call(skill: @skill, reference: "evolve.json")
    write_ref("evolve.json", '{"type":"object","properties":{"v2":{"type":"string"}},"required":["v2"]}')

    assert_no_difference "JsonSchema.count" do
      SchemaImporter.call(skill: @skill, reference: "evolve.json")
    end
    body = JSON.parse(JsonSchema.find_by(name: "sample__evolve").body)
    assert body["properties"].key?("v2")
  end

  test "returns :missing for non-existent reference" do
    result = SchemaImporter.call(skill: @skill, reference: "nope.json")
    assert_equal :missing, result.status
    assert_match(/not found/i, result.reason)
  end

  test "returns :invalid_json for malformed content" do
    write_ref("broken.json", "not json")
    result = SchemaImporter.call(skill: @skill, reference: "broken.json")
    assert_equal :invalid_json, result.status
    assert_match(/not valid JSON/i, result.reason)
  end

  test "rejects unknown set_default modes loudly" do
    assert_raises(ArgumentError) do
      SchemaImporter.call(skill: @skill, reference: "any.json", set_default: :sometimes)
    end
  end
end
