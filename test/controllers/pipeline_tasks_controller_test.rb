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

  test "POST execute rejects task without a workflow" do
    post execute_pipeline_task_path(pipeline_tasks(:draft_task))
    assert_redirected_to pipeline_task_path(pipeline_tasks(:draft_task))
    assert_equal "draft", pipeline_tasks(:draft_task).reload.status
  end

  test "POST execute promotes a draft and starts a run" do
    task = pipeline_tasks(:draft_task)
    task.update!(workflow: workflows(:deploy))

    assert_difference "Run.count", 1 do
      post execute_pipeline_task_path(task)
    end
    assert_redirected_to run_path(Run.last)
    assert_equal "running", task.reload.status
  end

  test "POST execute re-runs a completed task" do
    task = pipeline_tasks(:completed_task)
    assert_difference "Run.count", 1 do
      post execute_pipeline_task_path(task)
    end
    assert_redirected_to run_path(Run.last)
    assert_equal "running", task.reload.status
  end

  test "POST create with run_now launches immediately" do
    assert_difference ["PipelineTask.count", "Run.count"], 1 do
      assert_enqueued_with(job: ExecuteRunJob) do
        post pipeline_tasks_path, params: {
          run_now: "1",
          pipeline_task: {
            title: "Launch me", body: "right now",
            kind: "feature", project_id: projects(:seneschal).id,
            workflow_id: workflows(:deploy).id
          }
        }
      end
    end
    assert_redirected_to run_path(Run.last)
    assert_equal "running", PipelineTask.last.status
  end

  test "POST create with run_now but no workflow saves and warns" do
    assert_difference "PipelineTask.count", 1 do
      assert_no_difference "Run.count" do
        post pipeline_tasks_path, params: {
          run_now: "1",
          pipeline_task: {
            title: "No workflow", body: "yet",
            kind: "feature", project_id: projects(:seneschal).id
          }
        }
      end
    end
    assert_redirected_to pipeline_task_path(PipelineTask.last)
    assert_match "Assign a workflow", flash[:alert]
  end

  test "PATCH update with run_now launches immediately" do
    task = pipeline_tasks(:completed_task)
    assert_difference "Run.count", 1 do
      patch pipeline_task_path(task), params: {
        run_now: "1",
        pipeline_task: { title: task.title, body: "revised spec", kind: task.kind }
      }
    end
    assert_redirected_to run_path(Run.last)
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
