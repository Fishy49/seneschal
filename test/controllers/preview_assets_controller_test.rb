require "test_helper"

class PreviewAssetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
    @run_step = run_steps(:passed_step)
    @run = @run_step.run
    @tmp_root = Dir.mktmpdir
    Setting.create!(key: "run_assets_root", value: @tmp_root)
  end

  teardown do
    FileUtils.rm_rf(@tmp_root)
    Setting.find_by(key: "run_assets_root")&.destroy
  end

  test "GET show streams the file when it exists" do
    rel = "1/2/abc/cover.png"
    full = File.join(@tmp_root, rel)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, "PNGDATA")

    asset = PreviewAsset.create!(
      run_step: @run_step, run: @run, kind: "image",
      original_filename: "cover.png", content_type: "image/png",
      byte_size: File.size(full), storage_path: rel
    )

    get preview_asset_path(asset)
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal "PNGDATA", response.body
  end

  test "GET show returns 410 when the file is missing" do
    asset = PreviewAsset.create!(
      run_step: @run_step, run: @run, kind: "image",
      original_filename: "cover.png", content_type: "image/png",
      byte_size: 0, storage_path: "ghost/cover.png"
    )

    get preview_asset_path(asset)
    assert_response :gone
    assert_match(/no longer available/i, response.body)
  end
end
