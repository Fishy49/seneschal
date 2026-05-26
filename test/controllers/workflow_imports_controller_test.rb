require "test_helper"

class WorkflowImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
    @source_project = projects(:seneschal)
    @source_workflow = workflows(:deploy)
    @target_project = projects(:other_project)

    payload = WorkflowExporter.new(@source_workflow).call
    @upload = upload_for(payload)
  end

  test "GET new renders the import form" do
    get new_project_workflow_import_path(@target_project)
    assert_response :success
    assert_match "Import Workflow", response.body
  end

  test "POST create with mode=new imports a new workflow" do
    assert_difference "@target_project.workflows.count", 1 do
      post project_workflow_import_path(@target_project),
           params: { file: @upload, mode: "new" }
    end
    created = @target_project.workflows.find_by(name: "Deploy Pipeline")
    assert_not_nil created
    assert_redirected_to project_workflow_path(@target_project, created)
    assert_match(/Workflow imported/, flash[:notice])
  end

  test "POST create with mode=new honors name_override" do
    post project_workflow_import_path(@target_project),
         params: { file: @upload, mode: "new", name_override: "Imported Flow" }
    assert_not_nil @target_project.workflows.find_by(name: "Imported Flow")
  end

  test "POST create with mode=replace replaces the chosen workflow" do
    target_wf = @target_project.workflows.create!(name: "To Replace", trigger_type: "manual")
    target_wf.steps.create!(
      name: "Old step", step_type: "command", body: "echo old",
      position: 1, max_retries: 0, timeout: 60, config: {}
    )
    expected_step_count = @source_workflow.steps.count

    assert_no_difference "Workflow.count" do
      post project_workflow_import_path(@target_project),
           params: { file: @upload, mode: "replace", replace_workflow_id: target_wf.id }
    end
    target_wf.reload
    assert_equal expected_step_count, target_wf.steps.count
    assert_not target_wf.steps.exists?(name: "Old step")
    assert_redirected_to project_workflow_path(@target_project, target_wf)
    assert_match(/Workflow replaced/, flash[:notice])
  end

  test "POST create without a file shows an alert" do
    post project_workflow_import_path(@target_project), params: { mode: "new" }
    assert_redirected_to new_project_workflow_import_path(@target_project)
    assert_match(/select a file/, flash[:alert])
  end

  test "POST create with malformed JSON shows an alert" do
    bad = Rack::Test::UploadedFile.new(StringIO.new("not json"), "application/json", original_filename: "bad.json")
    post project_workflow_import_path(@target_project), params: { file: bad, mode: "new" }
    assert_redirected_to new_project_workflow_import_path(@target_project)
    assert_match(/Invalid JSON/, flash[:alert])
  end

  test "requires authentication" do
    delete logout_path
    get new_project_workflow_import_path(@target_project)
    assert_redirected_to login_path
  end

  private

  def upload_for(payload)
    Rack::Test::UploadedFile.new(
      StringIO.new(payload.to_json),
      "application/json",
      original_filename: "export.json"
    )
  end
end
