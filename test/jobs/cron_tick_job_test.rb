require "test_helper"

class CronTickJobTest < ActiveJob::TestCase
  setup do
    @task = pipeline_tasks(:ready_task)
    @task.update!(trigger_type: "cron", trigger_config: { "cron" => "0 * * * *" })
  end

  test "fires when a new expected cron time has passed" do
    # Pretend we last fired at 02:30 and it's now 03:05 -> the 03:00 tick is due.
    @task.record_cron_fire!(Time.zone.parse("2025-01-02 02:30:00"))
    now = Time.zone.parse("2025-01-02 03:05:00")

    assert_enqueued_with(job: ExecuteRunJob) do
      travel_to(now) { CronTickJob.perform_now }
    end

    assert_equal Time.zone.parse("2025-01-02 03:00:00"), @task.reload.last_fired_at
  end

  test "does not fire when no tick has passed since last fire" do
    @task.record_cron_fire!(Time.zone.parse("2025-01-02 03:00:00"))
    now = Time.zone.parse("2025-01-02 03:30:00")

    assert_no_enqueued_jobs only: ExecuteRunJob do
      travel_to(now) { CronTickJob.perform_now }
    end
  end

  test "skips ticks when the task is not executable" do
    @task.update!(status: "draft", workflow: nil)
    @task.record_cron_fire!(Time.zone.parse("2025-01-02 02:30:00"))
    now = Time.zone.parse("2025-01-02 03:05:00")

    assert_no_enqueued_jobs only: ExecuteRunJob do
      travel_to(now) { CronTickJob.perform_now }
    end
    # Still advance last_fired_at so we don't spam this check every minute.
    assert_equal Time.zone.parse("2025-01-02 03:00:00"), @task.reload.last_fired_at
  end

  test "ignores tasks with other trigger types" do
    manual = pipeline_tasks(:completed_task)
    assert_equal "manual", manual.trigger_type

    assert_no_enqueued_jobs only: ExecuteRunJob do
      CronTickJob.perform_now
    end
  end
end
