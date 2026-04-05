require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "valid setting" do
    s = Setting.new(key: "new_key", value: "new_value")
    assert s.valid?
  end

  test "requires key" do
    s = Setting.new(value: "x")
    assert_not s.valid?
    assert_includes s.errors[:key], "can't be blank"
  end

  test "requires unique key" do
    s = Setting.new(key: "claude_cli", value: "dup")
    assert_not s.valid?
  end

  test "bracket reader returns value" do
    assert_equal "claude 1.0.0", Setting["claude_cli"]
  end

  test "bracket reader returns nil for missing key" do
    assert_nil Setting["nonexistent"]
  end

  test "bracket writer creates new setting" do
    assert_difference "Setting.count", 1 do
      Setting["brand_new"] = "hello"
    end
    assert_equal "hello", Setting["brand_new"]
  end

  test "bracket writer updates existing setting" do
    Setting["claude_cli"] = "claude 2.0.0"
    assert_equal "claude 2.0.0", Setting["claude_cli"]
  end

  test "bracket writer converts to string" do
    Setting["numeric"] = 42
    assert_equal "42", Setting["numeric"]
  end
end
