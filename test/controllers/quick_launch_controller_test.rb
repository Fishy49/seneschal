require "test_helper"

class QuickLaunchControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET options returns projects with their workflows" do
    get quick_launch_options_path, as: :json
    assert_response :success

    projects = response.parsed_body["projects"]
    seneschal = projects.find { |p| p["id"] == projects(:seneschal).id }
    assert_equal "Seneschal", seneschal["name"]
    assert_equal "ready", seneschal["repo_status"]
    assert_includes seneschal["workflows"].pluck("name"), "Deploy Pipeline"
  end

  test "POST create writes a task and starts its run" do
    assert_difference ["PipelineTask.count", "Run.count"], 1 do
      assert_enqueued_with(job: ExecuteRunJob) do
        post quick_launch_path, params: {
          description: "Add rate limiting to the public API",
          project_id: projects(:seneschal).id,
          workflow_id: workflows(:deploy).id
        }, as: :json
      end
    end

    assert_response :success
    assert_equal run_path(Run.last), response.parsed_body["redirect"]

    task = PipelineTask.last
    assert_equal "Add rate limiting to the public API", task.title
    assert_equal "Add rate limiting to the public API", task.body
    assert_equal "feature", task.kind
    assert_equal "running", task.status
  end

  test "POST create titles from the first line and keeps the whole body" do
    post quick_launch_path, params: {
      description: "Ship the thing\n\nDetails follow here.",
      project_id: projects(:seneschal).id,
      workflow_id: workflows(:deploy).id
    }, as: :json

    assert_response :success
    task = PipelineTask.last
    assert_equal "Ship the thing", task.title
    assert_match "Details follow here.", task.body
  end

  test "POST create truncates a long title" do
    post quick_launch_path, params: {
      description: "x" * 200,
      project_id: projects(:seneschal).id,
      workflow_id: workflows(:deploy).id
    }, as: :json

    assert_response :success
    assert_equal 80, PipelineTask.last.title.length
  end

  test "POST create is unprocessable without a workflow" do
    assert_no_difference ["PipelineTask.count", "Run.count"] do
      post quick_launch_path, params: {
        description: "No workflow here",
        project_id: projects(:seneschal).id
      }, as: :json
    end

    assert_response :unprocessable_content
    assert_match(/workflow/i, response.parsed_body["error"])
  end

  test "POST create is unprocessable without a description" do
    assert_no_difference "PipelineTask.count" do
      post quick_launch_path, params: {
        description: "  ",
        project_id: projects(:seneschal).id,
        workflow_id: workflows(:deploy).id
      }, as: :json
    end

    assert_response :unprocessable_content
  end

  test "the palette and its keyboard hint render in the layout" do
    get root_path
    assert_response :success
    assert_select "[data-controller='command-palette']" do
      assert_select "[data-command-palette-target='description']"
      assert_select "[data-command-palette-target='project']"
      assert_select "[data-command-palette-target='workflow']"
    end
    assert_select "kbd", /K/
  end

  test "requires authentication" do
    delete logout_path
    get quick_launch_options_path
    assert_redirected_to login_path
  end
end
