require "test_helper"

class DataControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index renders data management page" do
    get data_management_path
    assert_response :success
    assert_select "h1", "Data Management"
  end

  test "GET index requires admin" do
    sign_out
    sign_in users(:other)
    get data_management_path
    assert_redirected_to root_path
  end

  test "GET export downloads JSON file" do
    get data_export_path
    assert_response :success
    assert_equal "application/json", response.media_type

    data = response.parsed_body
    assert_equal 1, data["seneschal_export"]["version"]
    assert data["seneschal_export"]["projects"].any?
  end

  test "POST import with valid file" do
    export_data = DataExporter.new.call
    file = Rack::Test::UploadedFile.new(
      StringIO.new(export_data.to_json), "application/json", false, original_filename: "export.json"
    )

    post data_import_path, params: { file: file }
    assert_redirected_to root_path
    follow_redirect!
    assert_select ".bg-success\\/15", /Import complete/
  end

  test "POST import without file redirects with error" do
    post data_import_path
    assert_redirected_to data_management_path
  end

  test "POST import with invalid JSON redirects with error" do
    file = Rack::Test::UploadedFile.new(
      StringIO.new("not json at all"), "application/json", false, original_filename: "bad.json"
    )

    post data_import_path, params: { file: file }
    assert_redirected_to data_management_path
  end
end
