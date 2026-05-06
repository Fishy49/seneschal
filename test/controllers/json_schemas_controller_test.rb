require "test_helper"

class JsonSchemasControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index renders schemas" do
    get json_schemas_path
    assert_response :success
    assert_select "h1", /JSON Schemas/i
  end

  test "GET new renders form" do
    get new_json_schema_path
    assert_response :success
  end

  test "GET show renders schema" do
    get json_schema_path(json_schemas(:person_schema))
    assert_response :success
    assert_select "h1", "person"
  end

  test "GET edit renders form" do
    get edit_json_schema_path(json_schemas(:person_schema))
    assert_response :success
  end

  test "POST create creates schema" do
    assert_difference "JsonSchema.count", 1 do
      post json_schemas_path, params: { json_schema: { name: "thing", body: '{"type":"object"}' } }
    end
    assert_redirected_to json_schema_path(JsonSchema.last)
    assert_equal "thing", JsonSchema.last.name
  end

  test "POST create rejects invalid JSON" do
    assert_no_difference "JsonSchema.count" do
      post json_schemas_path, params: { json_schema: { name: "bad", body: "{not json}" } }
    end
    assert_response :unprocessable_content
    assert_match "is not valid JSON", response.body
  end

  test "POST create rejects blank name" do
    assert_no_difference "JsonSchema.count" do
      post json_schemas_path, params: { json_schema: { name: "", body: '{"type":"object"}' } }
    end
    assert_response :unprocessable_content
  end

  test "PATCH update updates schema" do
    patch json_schema_path(json_schemas(:person_schema)), params: {
      json_schema: { description: "Updated description" }
    }
    assert_redirected_to json_schema_path(json_schemas(:person_schema))
    assert_equal "Updated description", json_schemas(:person_schema).reload.description
  end

  test "PATCH update rejects invalid JSON body" do
    patch json_schema_path(json_schemas(:person_schema)), params: {
      json_schema: { body: "{bad}" }
    }
    assert_response :unprocessable_content
  end

  test "DELETE destroy deletes unused schema" do
    assert_difference "JsonSchema.count", -1 do
      delete json_schema_path(json_schemas(:unused_schema))
    end
    assert_redirected_to json_schemas_path
  end

  test "DELETE destroy refuses to delete schema referenced by steps" do
    schema = json_schemas(:person_schema)
    @workflow = workflows(:deploy)
    @workflow.steps.create!(
      name: "Validator", step_type: "json_validator", position: 99,
      timeout: 30, max_retries: 0,
      config: { "json_schema_id" => schema.id, "source_variable" => "payload" }
    )

    assert_no_difference "JsonSchema.count" do
      delete json_schema_path(schema)
    end
    assert_redirected_to json_schemas_path
    assert_match "Cannot delete", flash[:alert]
  end
end
