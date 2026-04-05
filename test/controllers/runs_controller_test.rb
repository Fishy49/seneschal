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
end
