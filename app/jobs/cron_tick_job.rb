# Runs every minute. For each active cron-triggered task it figures out the
# most recent expected fire time. If we've moved past it since the last
# recorded fire, enqueues a run and advances last_fired_at.
#
# If many expected fires were missed (e.g. server was offline for a day), we
# still only fire once and jump last_fired_at forward to the most recent
# expected time. We never attempt to "catch up" by firing N times.
class CronTickJob < ApplicationJob
  queue_as :default

  def perform
    now = Time.current
    PipelineTask.scheduled_cron.find_each do |task|
      tick_one(task, now)
    rescue StandardError => e
      Rails.logger.error("CronTickJob failed for task #{task.id}: #{e.class}: #{e.message}")
    end
  end

  private

  def tick_one(task, now)
    cron = task.fugit_cron
    return unless cron

    anchor = task.last_fired_at || task.created_at

    most_recent = cron.previous_time(now).to_t
    return if most_recent <= anchor

    if task.executable?
      task.enqueue_run!(reason: "cron")
    else
      Rails.logger.info(
        "CronTickJob skipping task #{task.id}: not executable " \
        "(status=#{task.status}, workflow=#{task.workflow_id.inspect})"
      )
    end
    task.record_cron_fire!(most_recent)
  end
end
