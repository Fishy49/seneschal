require "test_helper"

class WorkflowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
    @project = projects(:seneschal)
    @workflow = workflows(:deploy)
  end

  test "GET show displays workflow" do
    get project_workflow_path(@project, @workflow)
    assert_response :success
  end

  test "GET new renders form" do
    get new_project_workflow_path(@project)
    assert_response :success
  end

  test "POST create with valid params" do
    assert_difference "Workflow.count", 1 do
      post project_workflows_path(@project), params: {
        workflow: { name: "New Workflow", trigger_type: "manual" }
      }
    end
    assert_redirected_to project_workflow_path(@project, Workflow.last)
  end

  test "POST create with invalid params" do
    assert_no_difference "Workflow.count" do
      post project_workflows_path(@project), params: {
        workflow: { name: "", trigger_type: "manual" }
      }
    end
    assert_response :unprocessable_content
  end

  test "GET edit renders form" do
    get edit_project_workflow_path(@project, @workflow)
    assert_response :success
  end

  test "PATCH update" do
    patch project_workflow_path(@project, @workflow), params: {
      workflow: { description: "Updated" }
    }
    assert_redirected_to project_workflow_path(@project, @workflow)
  end

  test "DELETE destroy removes workflow" do
    workflow = @project.workflows.create!(name: "Disposable", trigger_type: "manual")
    assert_difference "Workflow.count", -1 do
      delete project_workflow_path(@project, workflow)
    end
    assert_redirected_to project_path(@project)
  end

  test "POST trigger creates run and enqueues job" do
    assert_difference "Run.count", 1 do
      assert_enqueued_with(job: ExecuteRunJob) do
        post trigger_project_workflow_path(@project, @workflow), as: :json
      end
    end
  end

  test "PATCH update sets workflow.config[runner] when the form picks one" do
    patch project_workflow_path(@project, @workflow), params: {
      workflow: { name: @workflow.name, runner: "claude_sdk" }
    }
    assert_equal "claude_sdk", @workflow.reload.config["runner"]
  end

  test "PATCH update clears workflow.config[runner] when the form picks the default" do
    @workflow.update!(config: { "runner" => "claude_sdk" })
    patch project_workflow_path(@project, @workflow), params: {
      workflow: { name: @workflow.name, runner: "" }
    }
    assert_not @workflow.reload.config.key?("runner")
  end

  test "PATCH update refuses an unknown runner value rather than persisting garbage" do
    patch project_workflow_path(@project, @workflow), params: {
      workflow: { name: @workflow.name, runner: "fake_runner_lol" }
    }
    assert_not_includes @workflow.reload.config.fetch("runner", "missing"), "fake"
  end
end
