require "test_helper"

class PipelineTasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index lists tasks" do
    get pipeline_tasks_path
    assert_response :success
  end

  test "GET index filters by project" do
    get pipeline_tasks_path, params: { project_id: projects(:seneschal).id }
    assert_response :success
  end

  test "GET index filters by status" do
    get pipeline_tasks_path, params: { status: "ready" }
    assert_response :success
  end

  test "GET show displays task" do
    get pipeline_task_path(pipeline_tasks(:ready_task))
    assert_response :success
  end

  test "GET new renders form" do
    get new_pipeline_task_path
    assert_response :success
  end

  test "POST create with valid params" do
    assert_difference "PipelineTask.count", 1 do
      post pipeline_tasks_path, params: {
        pipeline_task: {
          title: "New Task", body: "Do something",
          kind: "feature", status: "draft",
          project_id: projects(:seneschal).id
        }
      }
    end
    assert_redirected_to pipeline_task_path(PipelineTask.last)
  end

  test "POST create with invalid params" do
    assert_no_difference "PipelineTask.count" do
      post pipeline_tasks_path, params: {
        pipeline_task: { title: "", body: "" }
      }
    end
    assert_response :unprocessable_content
  end

  test "PATCH mark_ready transitions task" do
    task = pipeline_tasks(:draft_task)
    task.update!(workflow: workflows(:deploy))
    patch mark_ready_pipeline_task_path(task)
    assert_redirected_to pipeline_task_path(task)
    assert_equal "ready", task.reload.status
  end

  test "PATCH mark_ready requires workflow" do
    task = pipeline_tasks(:draft_task)
    patch mark_ready_pipeline_task_path(task)
    assert_redirected_to pipeline_task_path(task)
    assert_equal "draft", task.reload.status
  end

  test "POST execute creates run and enqueues job" do
    task = pipeline_tasks(:ready_task)
    assert_difference "Run.count", 1 do
      assert_enqueued_with(job: ExecuteRunJob) do
        post execute_pipeline_task_path(task)
      end
    end
    assert_equal "running", task.reload.status
  end

  test "POST execute rejects non-executable task" do
    post execute_pipeline_task_path(pipeline_tasks(:draft_task))
    assert_redirected_to pipeline_task_path(pipeline_tasks(:draft_task))
  end

  test "DELETE destroy removes task" do
    task = PipelineTask.create!(
      title: "Temp", body: "temp", kind: "chore",
      status: "draft", project: projects(:seneschal)
    )
    assert_difference "PipelineTask.count", -1 do
      delete pipeline_task_path(task)
    end
    assert_redirected_to pipeline_tasks_path
  end
end
