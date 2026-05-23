class RunRecoveryJob < ApplicationJob
  queue_as :default

  # Why 30 min: a busy SDK step can sit quiet for 10+ minutes during MCP
  # cold-start (npx -y mcp-image), a long thinking turn, or an extended
  # Bash command without anything in the stream_log bumping updated_at.
  # 10 min was nuking those mid-flight; 30 is still tight enough to catch
  # genuinely-orphaned jobs within a handful of recovery ticks.
  STALE_THRESHOLD = 30.minutes

  def perform
    stale_run_steps = RunStep.where(status: "running")
                             .where(updated_at: ...STALE_THRESHOLD.ago)

    stale_run_steps.find_each do |run_step|
      run = run_step.run

      # Skip if already recovered once to prevent infinite loops
      next if run.system_flags["auto_recovered"]

      Rails.logger.info "[RunRecovery] Recovering stale RunStep ##{run_step.id} (Run ##{run.id}, step '#{run_step.step.name}')"

      # Mark the crashed step as failed
      run_step.update!(
        status: "failed",
        finished_at: Time.current,
        duration: run_step.started_at ? (Time.current - run_step.started_at) : 0,
        error_output: [run_step.error_output, "Interrupted unexpectedly. Auto-recovering."].compact.join("\n")
      )

      # Mark the run as failed, flag it as auto-recovered, then re-enqueue.
      # The flag lives on system_flags (not context) so it never leaks into
      # step env vars or prompt interpolation. Also drop `job_token`: if the
      # old worker is still alive (e.g. blocked on Open3 with a slow SDK
      # session), its next progress tick will see no token, then the new
      # job's token, and bail via Runners::Aborted instead of clobbering
      # the new attempt's stream_log.
      run.update!(
        status: "failed",
        error_message: "Step '#{run_step.step.name}' interrupted, auto-recovering",
        system_flags: run.system_flags.except("job_token").merge("auto_recovered" => true)
      )

      # Re-enqueue with resume to pick up from the crashed step
      ExecuteRunJob.perform_later(run, run_step.step_id, resume: true)

      Rails.logger.info "[RunRecovery] Re-enqueued Run ##{run.id} to resume from '#{run_step.step.name}'"
    end
  end
end
