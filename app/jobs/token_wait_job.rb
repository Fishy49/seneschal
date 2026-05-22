class TokenWaitJob < ApplicationJob
  queue_as :default

  # Cap on how often we wake to recheck a parked run. Claude's reset times
  # are usually accurate to within a few minutes, so 10 min is plenty of
  # padding without making the operator wait long after tokens are back.
  FALLBACK_INTERVAL = 10.minutes
  # Don't run forever — if we've been re-checking for a full day something
  # is wrong (operator probably wants to manually intervene).
  MAX_AGE = 24.hours

  # Schedule this job to fire at +reset_at+ (clamped to a sane window).
  def self.schedule(run, step_id, reset_at)
    fire_at = [reset_at || (Time.current + FALLBACK_INTERVAL), 30.seconds.from_now].max
    set(wait_until: fire_at).perform_later(run.id, step_id)
  end

  def perform(run_id, step_id)
    run = Run.find_by(id: run_id)
    return unless run
    return unless run.status == "waiting_for_tokens"

    # If the run has been parked for absurdly long, give up — somebody
    # needs to look at it.
    if run.waiting_until && Time.current > run.waiting_until + MAX_AGE
      run.update!(status: "failed", finished_at: Time.current,
                  error_message: "Gave up waiting for tokens after #{(MAX_AGE / 1.hour).to_i}h")
      return
    end

    # Reset hasn't arrived yet (we were woken early, or the queue is
    # running ahead of schedule): reschedule for the actual reset time.
    if run.waiting_until && Time.current < run.waiting_until
      self.class.schedule(run, step_id, run.waiting_until)
      return
    end

    resume_run(run, step_id)
  end

  private

  def resume_run(run, step_id)
    run_step = run.run_steps.where(step_id: step_id, status: "waiting_for_tokens").order(:position).last
    if run_step.nil?
      Rails.logger.warn("[TokenWaitJob] Run ##{run.id} has no waiting_for_tokens step for ##{step_id}; skipping resume")
      return
    end

    Rails.logger.info("[TokenWaitJob] Resuming run ##{run.id} at step ##{step_id}")
    # Flip the step back to "failed" so the resume branch in ExecuteRunJob
    # finds it as a "crashed" step and replays it in-place (incrementing
    # attempt, clearing prior output). The flip is invisible to the UI
    # because ExecuteRunJob immediately moves it to "running".
    run_step.update!(status: "failed")
    ExecuteRunJob.perform_later(run, step_id, resume: true)
  end
end
