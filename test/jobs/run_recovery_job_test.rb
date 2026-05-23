require "test_helper"

class RunRecoveryJobTest < ActiveJob::TestCase
  test "marks a stale running RunStep failed and clears the run's job_token" do
    run = runs(:active_run)
    run.update!(system_flags: { "job_token" => "stuck-worker" })
    step = steps(:command_step)
    run_step = run.run_steps.create!(
      step: step, status: "running", attempt: 1, position: 1,
      started_at: 1.hour.ago, updated_at: 1.hour.ago
    )

    # Bypass the timestamp callback so updated_at stays stale even after
    # the implicit touch from create!. Using update_columns sidesteps Rails'
    # auto-touch behavior.
    run_step.update_columns(updated_at: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations

    assert_enqueued_with(job: ExecuteRunJob) do
      RunRecoveryJob.new.perform
    end

    run.reload
    run_step.reload
    assert_equal "failed", run_step.status
    assert_includes run_step.error_output.to_s, "Interrupted unexpectedly"
    assert_equal "failed", run.status
    assert run.system_flags["auto_recovered"], "auto_recovered flag is set"
    assert_nil run.system_flags["job_token"], "job_token is cleared so orphan workers see mismatch"
  end

  test "skips recently-updated RunSteps even if status is running" do
    run = runs(:active_run)
    run.update!(system_flags: { "job_token" => "live-worker" })
    step = steps(:command_step)
    # Inside the threshold; should NOT be recovered.
    run.run_steps.create!(
      step: step, status: "running", attempt: 1, position: 1,
      started_at: 2.minutes.ago, updated_at: 2.minutes.ago
    )

    assert_no_enqueued_jobs(only: ExecuteRunJob) do
      RunRecoveryJob.new.perform
    end

    assert_equal "live-worker", run.reload.system_flags["job_token"]
  end

  test "skips a run that has already been auto-recovered once" do
    run = runs(:active_run)
    run.update!(system_flags: { "job_token" => "stuck-worker", "auto_recovered" => true })
    step = steps(:command_step)
    run_step = run.run_steps.create!(
      step: step, status: "running", attempt: 1, position: 1,
      started_at: 1.hour.ago
    )
    run_step.update_columns(updated_at: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations

    assert_no_enqueued_jobs(only: ExecuteRunJob) do
      RunRecoveryJob.new.perform
    end

    assert_equal "running", run_step.reload.status
  end
end
