class RunRecoveryJob < ApplicationJob
  queue_as :default

  STALE_THRESHOLD = 10.minutes

  def perform
    stale_run_steps = RunStep.where(status: "running")
                             .where(updated_at: ...STALE_THRESHOLD.ago)

    stale_run_steps.find_each do |run_step|
      run = run_step.run

      # Skip if already recovered once to prevent infinite loops
      next if run.context["auto_recovered"]

      Rails.logger.info "[RunRecovery] Recovering stale RunStep ##{run_step.id} (Run ##{run.id}, step '#{run_step.step.name}')"

      # Mark the crashed step as failed
      run_step.update!(
        status: "failed",
        finished_at: Time.current,
        duration: run_step.started_at ? (Time.current - run_step.started_at) : 0,
        error_output: [run_step.error_output, "Interrupted unexpectedly. Auto-recovering."].compact.join("\n")
      )

      # Mark the run as failed, flag it as auto-recovered, then re-enqueue
      run.update!(
        status: "failed",
        error_message: "Step '#{run_step.step.name}' interrupted, auto-recovering",
        context: run.context.merge("auto_recovered" => true)
      )

      # Re-enqueue with resume to pick up from the crashed step
      ExecuteRunJob.perform_later(run, run_step.step_id, resume: true)

      Rails.logger.info "[RunRecovery] Re-enqueued Run ##{run.id} to resume from '#{run_step.step.name}'"
    end
  end
end
