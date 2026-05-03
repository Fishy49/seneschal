require "test_helper"

class JsonSchemaValidatorTest < ActiveSupport::TestCase
  test "validates a matching document" do
    schema = json_schemas(:person_schema)
    validator = JsonSchemaValidator.new(schema)
    result = validator.validate({ "name" => "Rick", "age" => 30 })
    assert result[:valid]
    assert_empty result[:errors]
  end

  test "returns errors for non-matching document" do
    schema = json_schemas(:person_schema)
    validator = JsonSchemaValidator.new(schema)
    result = validator.validate({ "age" => 30 })
    assert_not result[:valid]
    assert result[:errors].any?
  end

  test "validates simple integer schema" do
    schema = json_schemas(:simple_schema)
    validator = JsonSchemaValidator.new(schema)
    assert validator.validate(42)[:valid]
    assert_not validator.validate("not an int")[:valid]
  end
end
