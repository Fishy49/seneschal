require "test_helper"

class SkillMdValidatorTest < ActiveSupport::TestCase
  test "valid frontmatter passes" do
    result = SkillMdValidator.validate("name" => "ingest", "description" => "Do a thing")
    assert result[:valid], result[:errors].inspect
    assert_empty result[:errors]
  end

  test "missing required name produces an error" do
    result = SkillMdValidator.validate("description" => "no name here")
    assert_not result[:valid]
    assert result[:errors].any? { |e| e.include?("name") }, result[:errors].inspect
  end

  test "missing required description produces an error" do
    result = SkillMdValidator.validate("name" => "only-name")
    assert_not result[:valid]
    assert result[:errors].any? { |e| e.include?("description") }, result[:errors].inspect
  end

  test "name with invalid type fails" do
    result = SkillMdValidator.validate("name" => 42, "description" => "x")
    assert_not result[:valid]
  end

  test "allowed-tools accepts a comma-separated string" do
    result = SkillMdValidator.validate(
      "name" => "x", "description" => "y", "allowed-tools" => "Read,Edit,Glob"
    )
    assert result[:valid], result[:errors].inspect
  end

  test "allowed-tools accepts an array of strings" do
    result = SkillMdValidator.validate(
      "name" => "x", "description" => "y", "allowed-tools" => ["Read", "Edit"]
    )
    assert result[:valid], result[:errors].inspect
  end

  test "allowed-tools rejects numeric arrays" do
    result = SkillMdValidator.validate(
      "name" => "x", "description" => "y", "allowed-tools" => [1, 2]
    )
    assert_not result[:valid]
  end

  test "extra unknown fields are tolerated" do
    result = SkillMdValidator.validate(
      "name" => "x", "description" => "y", "author" => "Rick", "license" => "MIT", "wat" => true
    )
    assert result[:valid], result[:errors].inspect
  end

  test "nil frontmatter is treated as empty and surfaces missing-required errors" do
    result = SkillMdValidator.validate(nil)
    assert_not result[:valid]
    combined = result[:errors].join(" | ")
    assert_includes combined, "name"
    assert_includes combined, "description"
  end
end
