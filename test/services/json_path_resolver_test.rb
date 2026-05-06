require "test_helper"

class JsonPathResolverTest < ActiveSupport::TestCase
  test "lookup returns the bare value when no dots in path" do
    assert_equal "hello", JsonPathResolver.lookup({ "msg" => "hello" }, "msg")
  end

  test "lookup parses string JSON and walks object path" do
    ctx = { "review" => '{"summary":"looks good","meta":{"author":"rick"}}' }
    assert_equal "looks good", JsonPathResolver.lookup(ctx, "review.summary")
    assert_equal "rick", JsonPathResolver.lookup(ctx, "review.meta.author")
  end

  test "lookup walks already-parsed Hash values" do
    ctx = { "review" => { "summary" => "ok" } }
    assert_equal "ok", JsonPathResolver.lookup(ctx, "review.summary")
  end

  test "lookup returns nil for missing root or missing key" do
    ctx = { "review" => '{"summary":"ok"}' }
    assert_nil JsonPathResolver.lookup(ctx, "missing.foo")
    assert_nil JsonPathResolver.lookup(ctx, "review.missing")
  end

  test "lookup returns nil when parent isn't valid JSON and path has dots" do
    assert_nil JsonPathResolver.lookup({ "x" => "not json" }, "x.foo")
  end

  test "format leaves scalars and JSON-encodes objects/arrays" do
    assert_equal "hello", JsonPathResolver.format("hello")
    assert_equal "42", JsonPathResolver.format(42)
    assert_includes JsonPathResolver.format([1, 2]), "1"
    assert_includes JsonPathResolver.format({ "a" => 1 }), '"a"'
  end

  test "paths_for_schema enumerates object property paths and descends into objects" do
    body = {
      "type" => "object",
      "properties" => {
        "summary" => { "type" => "string" },
        "meta" => {
          "type" => "object",
          "properties" => {
            "author" => { "type" => "string" },
            "tags" => { "type" => "array" }
          }
        }
      }
    }.to_json

    paths = JsonPathResolver.paths_for_schema(body, prefix: "review")
    assert_includes paths, "review.summary"
    assert_includes paths, "review.meta"
    assert_includes paths, "review.meta.author"
    assert_includes paths, "review.meta.tags"
    # Should not descend into array items
    assert_not(paths.any? { |p| p.include?("tags.") })
  end

  test "paths_for_schema returns empty for invalid JSON" do
    assert_equal [], JsonPathResolver.paths_for_schema("not json")
  end
end
