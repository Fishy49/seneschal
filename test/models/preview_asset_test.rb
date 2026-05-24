require "test_helper"

class PreviewAssetTest < ActiveSupport::TestCase
  setup do
    @run_step = run_steps(:passed_step)
    @run = @run_step.run
    @tmp_root = Dir.mktmpdir
    Setting.create!(key: "run_assets_root", value: @tmp_root)
  end

  teardown do
    FileUtils.rm_rf(@tmp_root)
    Setting.find_by(key: "run_assets_root")&.destroy
  end

  test "valid record persists" do
    asset = PreviewAsset.create!(
      run_step: @run_step, run: @run, kind: "image",
      original_filename: "cover.png", content_type: "image/png",
      byte_size: 1234, storage_path: "abc/cover.png"
    )
    assert asset.persisted?
  end

  test "rejects unknown kind" do
    asset = PreviewAsset.new(
      run_step: @run_step, run: @run, kind: "hologram",
      original_filename: "x.bin", storage_path: "x/x.bin", byte_size: 0
    )
    assert_not asset.valid?
    assert_includes asset.errors[:kind], "is not included in the list"
  end

  test "absolute_path resolves against assets_root when stored as relative" do
    asset = PreviewAsset.new(storage_path: "1/2/abc/cover.png")
    assert_equal "#{@tmp_root}/1/2/abc/cover.png", asset.absolute_path.to_s
  end

  test "absolute_path passes absolute storage_path through unchanged" do
    asset = PreviewAsset.new(storage_path: "/tmp/somewhere/cover.png")
    assert_equal "/tmp/somewhere/cover.png", asset.absolute_path.to_s
  end

  test "file_exists? returns true once the underlying file is written" do
    rel = "demo/here.png"
    full = File.join(@tmp_root, rel)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, "PNGDATA")
    asset = PreviewAsset.new(storage_path: rel)
    assert asset.file_exists?
  end

  test "file_exists? false when underlying file is missing" do
    asset = PreviewAsset.new(storage_path: "gone/file.png")
    assert_not asset.file_exists?
  end

  test "display_label falls back to filename" do
    asset = PreviewAsset.new(original_filename: "cover.png")
    assert_equal "cover.png", asset.display_label

    asset.label = "Title screen"
    assert_equal "Title screen", asset.display_label
  end

  test "run_step.preview_assets returns ordered list" do
    older = PreviewAsset.create!(
      run_step: @run_step, run: @run, kind: "image", original_filename: "a.png",
      storage_path: "a.png", byte_size: 1, content_type: "image/png",
      created_at: 2.hours.ago, updated_at: 2.hours.ago
    )
    newer = PreviewAsset.create!(
      run_step: @run_step, run: @run, kind: "image", original_filename: "b.png",
      storage_path: "b.png", byte_size: 1, content_type: "image/png"
    )
    assert_equal [older, newer], @run_step.preview_assets.to_a
  end
end
