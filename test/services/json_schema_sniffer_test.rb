require "test_helper"

class JsonSchemaSnifferTest < ActiveSupport::TestCase
  test "matches files with a $schema keyword" do
    assert JsonSchemaSniffer.looks_like_schema?('{"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object"}')
  end

  test "matches object-with-properties shape (no $schema)" do
    assert JsonSchemaSniffer.looks_like_schema?('{"type": "object", "properties": {"name": {"type": "string"}}}')
  end

  test "matches schemas using oneOf / anyOf / allOf" do
    assert JsonSchemaSniffer.looks_like_schema?('{"oneOf": [{"type": "string"}, {"type": "number"}]}')
    assert JsonSchemaSniffer.looks_like_schema?('{"anyOf": [{"type": "string"}]}')
    assert JsonSchemaSniffer.looks_like_schema?('{"allOf": [{"type": "string"}]}')
  end

  test "rejects plain config-style JSON" do
    assert_not JsonSchemaSniffer.looks_like_schema?('{"host": "example.com", "port": 443}')
  end

  test "rejects arrays at the root" do
    assert_not JsonSchemaSniffer.looks_like_schema?('[{"type": "object"}]')
  end

  test "rejects malformed JSON" do
    assert_not JsonSchemaSniffer.looks_like_schema?("{not json at all")
  end

  test "rejects empty / blank content" do
    assert_not JsonSchemaSniffer.looks_like_schema?(nil)
    assert_not JsonSchemaSniffer.looks_like_schema?("")
    assert_not JsonSchemaSniffer.looks_like_schema?("   ")
  end

  test "type: object alone is not enough without properties" do
    assert_not JsonSchemaSniffer.looks_like_schema?('{"type": "object"}')
  end
end
