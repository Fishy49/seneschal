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
end
