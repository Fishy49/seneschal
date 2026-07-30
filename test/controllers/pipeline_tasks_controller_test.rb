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

  test "POST create records the author" do
    post pipeline_tasks_path, params: {
      pipeline_task: {
        title: "Attributed", body: "who made this",
        kind: "feature", project_id: projects(:seneschal).id
      }
    }
    assert_equal users(:admin), PipelineTask.last.created_by
  end

  test "POST execute records who started the run" do
    post execute_pipeline_task_path(pipeline_tasks(:ready_task))
    assert_equal users(:admin), Run.last.started_by
    assert_equal users(:admin).email, Run.last.started_by_label
  end

  test "POST create records a task.created event" do
    assert_difference "Event.count", 1 do
      post pipeline_tasks_path, params: {
        pipeline_task: {
          title: "Feed me", body: "b", kind: "feature",
          project_id: projects(:seneschal).id
        }
      }
    end
    event = Event.recent.first
    assert_equal "task.created", event.action
    assert_equal users(:admin), event.user
  end

  test "POST execute records a run.started event" do
    post execute_pipeline_task_path(pipeline_tasks(:ready_task))
    assert_equal "run.started", Event.recent.first.action
    assert_equal Run.last, Event.recent.first.subject
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

  test "POST create rejects a workflow from another project" do
    foreign = projects(:other_project).workflows.create!(name: "Foreign")
    assert_no_difference "PipelineTask.count" do
      post pipeline_tasks_path, params: {
        pipeline_task: {
          title: "Crafted", body: "mismatch",
          kind: "feature", project_id: projects(:seneschal).id,
          workflow_id: foreign.id
        }
      }
    end
    assert_response :unprocessable_content
  end

  test "GET new offers a workflow card per workflow, tagged with its project" do
    get new_pipeline_task_path
    assert_select "label[data-project-id=?]", projects(:seneschal).id.to_s
    assert_select "input[type=radio][name=?][value=?]",
                  "pipeline_task[workflow_id]", workflows(:deploy).id.to_s
  end

  test "GET new offers a draft card that selects no workflow" do
    get new_pipeline_task_path
    assert_select "input[type=radio][name=?][value=?]", "pipeline_task[workflow_id]", ""
  end

  test "the composer prefills from the palette handoff" do
    get new_pipeline_task_path, params: {
      description: "Add rate limiting to the public endpoints",
      project_id: projects(:seneschal).id
    }
    assert_select "input[name=?][value=?]", "pipeline_task[title]", "Add rate limiting to the public endpoints"
    assert_select "input[name=?][value=?]", "pipeline_task[body]", "Add rate limiting to the public endpoints"
    assert_select "select[name=?] option[selected][value=?]", "pipeline_task[project_id]", projects(:seneschal).id.to_s
  end

  test "when to run is a chip row, not a select" do
    get new_pipeline_task_path
    assert_select "input[type=radio][name=?][value=?]", "pipeline_task[trigger_type]", "manual"
    assert_select "input[type=radio][name=?][value=?]", "pipeline_task[trigger_type]", "cron"
    assert_select "select[name=?]", "pipeline_task[trigger_type]", count: 0
  end

  test "kind is optional and defaults to feature" do
    post pipeline_tasks_path, params: {
      pipeline_task: {
        title: "No tag given", body: "Do the thing",
        project_id: projects(:seneschal).id, workflow_id: workflows(:deploy).id,
        status: "ready", trigger_type: "manual"
      }
    }
    assert_response :redirect
    assert_equal "feature", PipelineTask.find_by(title: "No tag given").kind
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
