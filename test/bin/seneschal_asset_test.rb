require "test_helper"
require "open3"
require "tmpdir"
require "sqlite3"

class SeneschalAssetWrapperTest < ActiveSupport::TestCase
  WRAPPER = Rails.root.join("bin/seneschal-asset").to_s

  setup do
    @tmpdir      = Dir.mktmpdir
    @db_path     = File.join(@tmpdir, "test.sqlite3")
    @assets_root = File.join(@tmpdir, "assets")
    @source_dir  = File.join(@tmpdir, "src")
    FileUtils.mkdir_p(@assets_root)
    FileUtils.mkdir_p(@source_dir)

    db = SQLite3::Database.new(@db_path)
    db.execute("CREATE TABLE run_steps (id INTEGER PRIMARY KEY, run_id INTEGER)")
    db.execute(<<~SQL.squish)
      CREATE TABLE preview_assets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_step_id INTEGER NOT NULL,
        run_id INTEGER NOT NULL,
        kind TEXT NOT NULL,
        label TEXT,
        original_filename TEXT NOT NULL,
        content_type TEXT,
        byte_size INTEGER NOT NULL DEFAULT 0,
        storage_path TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    SQL
    db.execute("INSERT INTO run_steps (id, run_id) VALUES (?, ?)", [42, 7])
    db.close
  end

  teardown { FileUtils.rm_rf(@tmpdir) }

  def run_wrapper(*, run_step_id: "42", run_id: "7")
    env = {
      "SENESCHAL_DB_PATH" => @db_path,
      "SENESCHAL_RUN_ID" => run_id,
      "SENESCHAL_RUN_STEP_ID" => run_step_id,
      "SENESCHAL_ASSETS_ROOT" => @assets_root
    }
    stdout, stderr, status = Open3.capture3(env, WRAPPER, *)
    [stdout, stderr, status.exitstatus]
  end

  def all_rows
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true
    db.execute("SELECT * FROM preview_assets")
  end

  def write_source(name, body = "DATA")
    path = File.join(@source_dir, name)
    File.write(path, body)
    path
  end

  test "registers an image asset, copies the file, and inserts a row" do
    source = write_source("cover.png", "PNGBYTES")
    stdout, stderr, code = run_wrapper("register", "--path", source, "--label", "Title")
    assert_equal 0, code, "wrapper failed: #{stderr}"
    assert_match(/Registered image asset #\d+: Title/, stdout)

    row = all_rows.first
    assert_equal "image", row["kind"]
    assert_equal "Title", row["label"]
    assert_equal "cover.png", row["original_filename"]
    assert_equal "image/png", row["content_type"]
    assert_equal 8, row["byte_size"]
    assert_equal 42, row["run_step_id"]
    assert_equal 7,  row["run_id"]

    copied = File.join(@assets_root, row["storage_path"])
    assert File.exist?(copied), "expected copied file at #{copied}"
    assert_equal "PNGBYTES", File.read(copied)
  end

  test "infers kind from extension for audio and video" do
    audio = write_source("clip.mp3", "ID3DATA")
    _, _, code = run_wrapper("register", "--path", audio)
    assert_equal 0, code
    assert_equal "audio", all_rows.first["kind"]
    assert_equal "audio/mpeg", all_rows.first["content_type"]

    video = write_source("scene.mp4", "MP4")
    _, _, code = run_wrapper("register", "--path", video)
    assert_equal 0, code
    assert_equal "video", all_rows.last["kind"]
  end

  test "explicit --kind overrides extension inference" do
    source = write_source("weird.bin", "X")
    _, _, code = run_wrapper("register", "--path", source, "--kind", "image")
    assert_equal 0, code
    assert_equal "image", all_rows.first["kind"]
  end

  test "fails when kind cannot be inferred and is not provided" do
    source = write_source("mystery.xyz", "X")
    _, stderr, code = run_wrapper("register", "--path", source)
    assert_equal 1, code
    assert_match(/could not infer asset kind/, stderr)
    assert_empty all_rows
  end

  test "fails when --kind is invalid" do
    source = write_source("cover.png", "X")
    _, stderr, code = run_wrapper("register", "--path", source, "--kind", "hologram")
    assert_equal 1, code
    assert_match(/invalid --kind/, stderr)
  end

  test "fails when --path is missing" do
    _, stderr, code = run_wrapper("register", "--label", "lol")
    assert_equal 1, code
    assert_match(/--path is required/, stderr)
  end

  test "fails when the source file does not exist" do
    _, stderr, code = run_wrapper("register", "--path", "/no/such/file.png")
    assert_equal 1, code
    assert_match(/file not found/, stderr)
  end

  test "rejects mismatched run_step / run pairing" do
    source = write_source("cover.png", "X")
    _, stderr, code = run_wrapper("register", "--path", source, run_id: "999")
    assert_equal 1, code
    assert_match(/does not belong to run 999/, stderr)
    assert_empty all_rows
  end

  test "fails when SENESCHAL_ASSETS_ROOT is unset" do
    source = write_source("cover.png", "X")
    env = {
      "SENESCHAL_DB_PATH" => @db_path,
      "SENESCHAL_RUN_ID" => "7",
      "SENESCHAL_RUN_STEP_ID" => "42",
      "SENESCHAL_ASSETS_ROOT" => nil
    }
    _, stderr, code = Open3.capture3(env, WRAPPER, "register", "--path", source).then { |o, e, s| [o, e, s.exitstatus] }
    assert_equal 1, code
    assert_match(/SENESCHAL_ASSETS_ROOT not set/, stderr)
  end
end
