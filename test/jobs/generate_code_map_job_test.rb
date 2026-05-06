require "test_helper"

class GenerateCodeMapJobTest < ActiveSupport::TestCase
  setup { @job = GenerateCodeMapJob.new }

  test "drops hallucinated paths from file_index and modules" do
    analysis = {
      "modules" => [
        { "name" => "Docs", "description" => "Docs", "files" => ["README.md", "GHOST.rb"] },
        { "name" => "Phantom", "description" => "Imaginary", "files" => ["NOPE.rb"] }
      ],
      "file_index" => {
        "README.md" => { "summary" => "readme", "module" => "Docs", "language" => "markdown" },
        "GHOST.rb" => { "summary" => "ghost", "module" => "Phantom", "language" => "ruby" }
      }
    }

    result = @job.send(:enforce_tree_consistency, analysis, ["README.md"])

    assert_equal({ "README.md" => { "summary" => "readme", "module" => "Docs", "language" => "markdown" } }, result["file_index"])
    assert_equal 1, result["modules"].size
    assert_equal "Docs", result["modules"].first["name"]
    assert_equal ["README.md"], result["modules"].first["files"]
  end

  test "backfills files Claude omitted with empty summaries" do
    analysis = {
      "modules" => [{ "name" => "Docs", "description" => "Docs", "files" => ["README.md"] }],
      "file_index" => {
        "README.md" => { "summary" => "readme", "module" => "Docs", "language" => "markdown" }
      }
    }

    result = @job.send(:enforce_tree_consistency, analysis, ["README.md", "GAME.md", "src/main.rb"])

    assert_equal 3, result["file_index"].size
    assert_equal "", result["file_index"]["GAME.md"]["summary"]
    assert_equal "markdown", result["file_index"]["GAME.md"]["language"]
    assert_equal "ruby", result["file_index"]["src/main.rb"]["language"]
    assert_equal "Docs", result["file_index"]["GAME.md"]["module"]
    assert_includes result["modules"].first["files"], "GAME.md"
    assert_includes result["modules"].first["files"], "src/main.rb"
  end

  test "creates an Uncategorized module when Claude returns no modules" do
    analysis = { "modules" => [], "file_index" => {} }

    result = @job.send(:enforce_tree_consistency, analysis, ["README.md"])

    assert_equal 1, result["modules"].size
    assert_equal "Uncategorized", result["modules"].first["name"]
    assert_equal ["README.md"], result["modules"].first["files"]
    assert_equal "Uncategorized", result["file_index"]["README.md"]["module"]
  end

  test "handles non-Hash module entries and missing keys gracefully" do
    analysis = { "modules" => [nil, "garbage", { "name" => "Docs", "files" => nil }], "file_index" => "bogus" }

    result = @job.send(:enforce_tree_consistency, analysis, ["a.rb"])

    assert_equal 1, result["modules"].size
    assert_equal ["a.rb"], result["modules"].first["files"]
    assert result["file_index"].key?("a.rb")
  end
end
