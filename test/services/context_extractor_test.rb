require "test_helper"

class ContextExtractorTest < ActiveSupport::TestCase
  test "extracts matching patterns from stdout" do
    patterns = { "pr_number" => 'PR #(\d+)', "branch" => 'branch (feature/\S+)' }
    stdout = "PR #42 created on branch feature/add-auth"
    result = ContextExtractor.new(patterns, stdout).extract
    assert_equal "42", result["pr_number"]
    assert_equal "feature/add-auth", result["branch"]
  end

  test "ignores non-matching patterns" do
    patterns = { "pr_number" => 'PR #(\d+)', "missing" => 'NOTFOUND (\w+)' }
    stdout = "PR #42 created"
    result = ContextExtractor.new(patterns, stdout).extract
    assert_equal "42", result["pr_number"]
    assert_not_includes result.keys, "missing"
  end

  test "handles nil patterns" do
    result = ContextExtractor.new(nil, "some output").extract
    assert_equal({}, result)
  end

  test "handles nil stdout" do
    result = ContextExtractor.new({ "x" => '(\d+)' }, nil).extract
    assert_equal({}, result)
  end

  test "handles empty stdout" do
    result = ContextExtractor.new({ "x" => '(\d+)' }, "").extract
    assert_equal({}, result)
  end

  test "captures first group only" do
    patterns = { "version" => 'v(\d+)\.(\d+)' }
    stdout = "Released v2.5"
    result = ContextExtractor.new(patterns, stdout).extract
    assert_equal "2", result["version"]
  end
end
