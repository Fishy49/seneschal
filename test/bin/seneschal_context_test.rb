require "test_helper"
require "open3"
require "tmpdir"
require "sqlite3"

class SeneschalContextWrapperTest < ActiveSupport::TestCase
  WRAPPER = Rails.root.join("bin/seneschal-context").to_s

  setup do
    @tmpdir = Dir.mktmpdir
    @db_path = File.join(@tmpdir, "test.sqlite3")
    db = SQLite3::Database.new(@db_path)
    db.execute("CREATE TABLE runs (id INTEGER PRIMARY KEY, context TEXT)")
    db.execute(<<~SQL.squish)
      CREATE TABLE context_query_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_step_id INTEGER, variable TEXT, expression TEXT,
        returned_bytes INTEGER, error TEXT,
        created_at TEXT, updated_at TEXT
      )
    SQL
    db.execute("INSERT INTO runs (id, context) VALUES (?, ?)",
               [1, { "foundation" => { "title" => "Hello", "items" => [{ "name" => "a" }, { "name" => "b" }] } }.to_json])
    db.close
  end

  teardown { FileUtils.rm_rf(@tmpdir) }

  def run_wrapper(*, queryable: "foundation")
    env = {
      "SENESCHAL_DB_PATH" => @db_path,
      "SENESCHAL_RUN_ID" => "1",
      "SENESCHAL_RUN_STEP_ID" => "42",
      "SENESCHAL_QUERYABLE_VARS" => queryable
    }
    stdout, stderr, status = Open3.capture3(env, WRAPPER, *)
    [stdout, stderr, status.exitstatus]
  end

  def log_rows
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true
    db.execute("SELECT variable, expression, returned_bytes, error FROM context_query_logs")
  end

  test "extracts a top-level field via jq filter" do
    stdout, _, code = run_wrapper("foundation", ".title")
    assert_equal 0, code
    assert_equal "\"Hello\"\n", stdout
    log = log_rows.last
    assert_equal "foundation", log["variable"]
    assert_equal ".title", log["expression"]
    assert log["returned_bytes"].positive?
    assert_nil log["error"]
  end

  test "supports jq pipeline expressions" do
    stdout, _, code = run_wrapper("foundation", ".items | length")
    assert_equal 0, code
    assert_equal "2\n", stdout
  end

  test "denies access to variables not in SENESCHAL_QUERYABLE_VARS" do
    _, stderr, code = run_wrapper("secrets", ".api_key", queryable: "foundation")
    assert_equal 1, code
    assert_match(/not queryable/, stderr)
    log = log_rows.last
    assert_equal "secrets", log["variable"]
    assert_match(/not queryable/, log["error"])
    assert_equal 0, log["returned_bytes"]
  end

  test "logs jq failures with the stderr message" do
    _, stderr, code = run_wrapper("foundation", ".nonexistent | error(\"nope\")")
    assert_equal 1, code
    assert_match(/nope/, stderr)
    log = log_rows.last
    assert_match(/nope/, log["error"])
  end

  test "errors when variable is missing from run context" do
    db = SQLite3::Database.new(@db_path)
    db.execute("UPDATE runs SET context = ? WHERE id = 1", ["{}"])
    db.close
    _, stderr, code = run_wrapper("foundation", ".title")
    assert_equal 1, code
    assert_match(/not found in run context/, stderr)
  end
end
