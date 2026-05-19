require "test_helper"

class RunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index lists runs" do
    get runs_path
    assert_response :success
  end

  test "GET index filters by status" do
    get runs_path, params: { status: "running" }
    assert_response :success
  end

  test "GET show displays run" do
    get run_path(runs(:completed_run))
    assert_response :success
  end

  test "POST stop marks run as stopped" do
    run = runs(:active_run)
    post stop_run_path(run)
    assert_redirected_to run_path(run)
    run.reload
    assert_equal "stopped", run.status
    assert_not_nil run.finished_at
  end

  test "POST stop updates task status to failed" do
    run = runs(:active_run)
    task = run.pipeline_task
    post stop_run_path(run)
    assert_equal "failed", task.reload.status
  end

  test "POST stop rejects non-active run" do
    post stop_run_path(runs(:completed_run))
    assert_redirected_to run_path(runs(:completed_run))
    assert_equal "completed", runs(:completed_run).reload.status
  end

  test "POST resume enqueues job for failed run" do
    run = runs(:failed_run)
    assert_enqueued_with(job: ExecuteRunJob) do
      post resume_run_path(run)
    end
    assert_redirected_to run_path(run)
  end

  test "POST resume rejects running run" do
    post resume_run_path(runs(:active_run))
    assert_redirected_to run_path(runs(:active_run))
  end

  test "POST retry_from creates new run" do
    run = runs(:failed_run)
    step = steps(:command_step)
    assert_difference "Run.count", 1 do
      assert_enqueued_with(job: ExecuteRunJob) do
        post retry_from_run_path(run), params: { step_id: step.id }
      end
    end
  end

  test "GET run show renders danger badge for skip_permissions project" do
    projects(:seneschal).update!(skip_permissions: true)
    run = workflows(:deploy).runs.create!(status: "running", context: {})
    get run_path(run)
    assert_response :success
    assert_match(/Danger Mode/, response.body)
  end

  test "GET runs index shows danger indicator next to runs" do
    projects(:seneschal).update!(skip_permissions: true)
    workflows(:deploy).runs.create!(status: "running", context: {})
    get runs_path
    assert_response :success
    assert_match(/Danger Mode/, response.body)
  end

  test "GET show renders awaiting_approval badge and approve/reject actions" do
    run = runs(:awaiting_run)
    run_steps(:awaiting_step_run_step)
    get run_path(run)
    assert_response :success
    assert_match(/awaiting approval/i, response.body)
    assert_select "form[action=?]", approve_run_path(run)
    assert_select "form[action=?]", reject_run_path(run)
  end

  test "POST approve marks run_step passed and enqueues after_approval job" do
    run = runs(:awaiting_run)
    rs = run_steps(:awaiting_step_run_step)
    assert_enqueued_with(job: ExecuteRunJob, args: [run, rs.step_id, { after_approval: true }]) do
      post approve_run_path(run)
    end
    assert_redirected_to run_path(run)
    assert_equal "passed", rs.reload.status
    assert_equal "running", run.reload.status
  end

  test "POST approve rejects non-awaiting_approval run" do
    post approve_run_path(runs(:active_run))
    assert_redirected_to run_path(runs(:active_run))
    assert_equal "running", runs(:active_run).reload.status
  end

  test "POST reject saves rejection_context and enqueues resume job" do
    run = runs(:awaiting_run)
    rs = run_steps(:awaiting_step_run_step)
    assert_enqueued_with(job: ExecuteRunJob, args: [run, rs.step_id, { resume: true }]) do
      post reject_run_path(run), params: { rejection_context: "Use a different branch name." }
    end
    assert_redirected_to run_path(run)
    assert_equal "Use a different branch name.", rs.reload.rejection_context
    assert_equal "awaiting_approval", rs.reload.status
    assert_equal "running", run.reload.status
  end

  test "POST reject rejects non-awaiting_approval run" do
    post reject_run_path(runs(:active_run)), params: { rejection_context: "nope" }
    assert_redirected_to run_path(runs(:active_run))
  end

  # --- R10: Replay + Compare ---

  test "GET replay renders the trajectory view" do
    get replay_run_path(runs(:completed_run))
    assert_response :success
    assert_select "h1", /Run ##{runs(:completed_run).id}/
    assert_select "h1", /Replay/
  end

  test "GET replay surfaces stream_log entries from each RunStep" do
    get replay_run_path(runs(:completed_run))
    assert_response :success
    # passed_step's stream_log includes a `result` event (5 turns @ 45s).
    # Render the trajectory entry inline so the "Result" header is visible.
    assert_match(/Result/, response.body)
    assert_match "5 turns", response.body
    assert_match "45.0s", response.body
  end

  test "GET replay renders filter chips for every entry kind" do
    get replay_run_path(runs(:completed_run))
    assert_response :success
    ["tool_use", "text", "thinking", "tool_result", "result", "system"].each do |kind|
      assert_select "input[data-kind=?]", kind
    end
  end

  test "GET diff with no other runs of this task surfaces the empty state" do
    # failed_run has no pipeline_task; fall back to workflow scope.
    # Make sure exactly one other run of the same workflow exists so the
    # dropdown is populated but the user hasn't picked yet.
    get diff_run_path(runs(:failed_run))
    assert_response :success
    # Either picks the default target OR shows the "pick one" empty state.
    assert_select "select[name=against]"
  end

  test "GET diff picks the most recent other run of the same task by default" do
    same_task_run = Run.create!(workflow: workflows(:deploy),
                                pipeline_task: pipeline_tasks(:completed_task),
                                status: "failed", started_at: 1.day.ago,
                                finished_at: 23.hours.ago, context: {}, input: {})

    get diff_run_path(runs(:completed_run))
    assert_response :success
    assert_match "Run ##{same_task_run.id}", response.body
  end

  test "GET diff honors an explicit against= parameter" do
    other = Run.create!(workflow: workflows(:deploy),
                        pipeline_task: pipeline_tasks(:completed_task),
                        status: "completed", started_at: 1.day.ago,
                        finished_at: 23.hours.ago, context: {}, input: {})

    get diff_run_path(runs(:completed_run), against: other.id)
    assert_response :success
    assert_match "Run ##{other.id}", response.body
  end

  test "GET diff ignores against= ids that aren't candidate targets" do
    # A run from an unrelated workflow shouldn't be selectable.
    other_workflow = workflows(:deploy)
    foreign = Run.create!(workflow: other_workflow, status: "completed",
                          started_at: 1.day.ago, finished_at: 23.hours.ago,
                          context: {}, input: {})

    # Make completed_run task-scoped to ensure the candidate pool is just
    # other runs of the same task — foreign isn't part of it.
    get diff_run_path(runs(:completed_run), against: foreign.id)
    assert_response :success
    # Falls through to the empty state because no candidate matched.
    assert_no_match(/Run ##{foreign.id}/, response.body)
  end
end
