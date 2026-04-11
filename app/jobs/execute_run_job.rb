require "open3"

class ExecuteRunJob < ApplicationJob
  queue_as :default

  def perform(run, resume_from_step_id = nil, resume: false)
    project = run.workflow.project
    unless project.repo_ready?
      run.update!(status: "failed", finished_at: Time.current,
                  error_message: "Repository not cloned. Clone it from the project page first.")
      sync_task_status(run)
      broadcast_run(run)
      return
    end

    # Claim this run with a unique token. If another ExecuteRunJob gets enqueued
    # for the same run (e.g. via RunRecoveryJob), it'll overwrite this token and
    # our loop will bail on the next iteration.
    @job_token = SecureRandom.hex(8)
    run.update!(
      status: "running",
      started_at: run.started_at || Time.current,
      system_flags: (run.system_flags || {}).merge("job_token" => @job_token)
    )
    run.update!(error_message: nil, finished_at: nil) if resume
    broadcast_run(run)
    repo_path = project.local_path

    system("git", "-C", repo_path, "pull", "--ff-only")

    # Build the execution queue from workflow steps + any run-scoped ad-hoc steps
    # (ad-hoc steps are appended by "Follow Up" and run after the workflow completes).
    # Queue entries are [step, queued_run_step_id] tuples.
    workflow_steps = run.workflow.steps.where(injectable_only: false).to_a
    ad_hoc_steps = run.ad_hoc_steps.where(injectable_only: false).to_a
    all_steps = workflow_steps + ad_hoc_steps
    queue = all_steps.map { |s| [s, nil] }
    injection_count = 0

    if resume && resume_from_step_id.present?
      # Resuming an existing run: skip steps already executed, pick up position counter
      position = run.run_steps.maximum(:position) || 0

      # Drop everything before the resume step from the queue
      queue.shift while queue.any? && queue.first[0].id != resume_from_step_id

      # Link the existing failed RunStep so we can reuse its session_id
      crashed_run_step = run.run_steps.where(step_id: resume_from_step_id, status: "failed").last
      queue[0] = [queue[0][0], crashed_run_step.id] if crashed_run_step && queue.any?
    elsif resume_from_step_id.present?
      # New run with skip: create skipped RunSteps for steps before the resume point
      position = 0
      while queue.any? && queue.first[0].id != resume_from_step_id
        step, = queue.shift
        position += 1
        rs = run.run_steps.create!(step: step, status: "skipped", attempt: 1, position: position,
                                   started_at: Time.current, finished_at: Time.current, duration: 0)
        broadcast_step(run, rs)
      end
    else
      position = 0
    end

    while queue.any?
      step, queued_run_step_id = queue.shift
      run.reload
      return if run.status == "stopped"
      return if run.system_flags["job_token"] != @job_token

      position += 1

      # Resolve input context for this execution
      resolved_context = resolve_input_context(step, run.context)

      # Use existing queued RunStep if one was pre-created during injection, otherwise create new
      if queued_run_step_id
        run_step = run.run_steps.find(queued_run_step_id)
        run_step.update!(
          status: "running", started_at: Time.current,
          position: position, resolved_input_context: resolved_context
        )
      else
        run_step = run.run_steps.create!(
          step: step, status: "running", attempt: 1,
          position: position, started_at: Time.current,
          resolved_input_context: resolved_context
        )
      end
      broadcast_run(run) # Full refresh to show the new step in the list

      result = execute_with_retries(run, run_step, step, repo_path, resolved_context)

      if result.passed?
        complete_step(run, run_step, step, result)
      else
        fail_step(run, run_step, result)

        # Check for on_failure_inject
        inject_steps = step.config["on_failure_inject"]
        max_injections = step.config.fetch("max_injections", 3)

        if inject_steps.present? && injection_count < max_injections
          injection_count += 1

          # Inject failure context for the next step to consume
          run.update!(context: run.context.merge(
            "previous_failure" => [result.stdout, result.stderr].compact.join("\n"),
            "previous_failure_step" => step.name,
            "injection_round" => injection_count.to_s
          ))

          # Look up the named steps, create queued RunSteps, and prepend to queue
          steps_to_inject = inject_steps.filter_map do |name|
            run.workflow.steps.find_by(name: name)
          end

          if steps_to_inject.any?
            queued_entries = steps_to_inject.map do |s|
              rs = run.run_steps.create!(step: s, status: "queued", attempt: 1, position: 0)
              [s, rs.id]
            end
            queue.unshift(*queued_entries)
            broadcast_run(run)
            next
          end
        end

        run.update!(status: "failed", finished_at: Time.current, error_message: "Step '#{step.name}' failed")
        sync_task_status(run)
        broadcast_run(run)
        return
      end
    end

    run.update!(status: "completed", finished_at: Time.current)
    sync_task_status(run)
    broadcast_run(run)
  end

  private

  def resolve_input_context(step, context)
    return nil if step.input_context.blank?

    any_resolved = false
    resolved = step.input_context.gsub(/\$\{(\w+)\}/) do
      value = context[::Regexp.last_match(1)] || context[::Regexp.last_match(1).to_sym]
      if value.present?
        any_resolved = true
        value
      else
        ""
      end
    end

    return nil unless any_resolved

    resolved = resolved.strip
    resolved.presence
  end

  def execute_with_retries(run, run_step, step, repo_path, resolved_context = nil)
    # If resuming a crashed skill/prompt step, pass the session_id so Claude can continue
    resume_sid = run_step.claude_session_id if step.step_type.in?(["skill", "prompt"])

    executor = StepExecutor.new(step, run.context, repo_path,
                                resolved_input_context: resolved_context,
                                resume_session_id: resume_sid)

    on_progress = lambda { |update|
      # Always bump updated_at so RunRecoveryJob's stale detection doesn't
      # falsely trigger on long-running steps (e.g. CI polling). update_all
      # skips Rails' automatic timestamp touching.
      attrs = { updated_at: Time.current }
      attrs[:output] = update[:output] if update.key?(:output)
      attrs[:error_output] = update[:error_output] if update.key?(:error_output)
      attrs[:stream_log] = update[:stream_log] if update.key?(:stream_log)
      attrs[:claude_session_id] = update[:claude_session_id] if update[:claude_session_id].present?
      RunStep.where(id: run_step.id).update_all(attrs)
      run_step.reload
      # Broadcast the full step (not just stream_log) to avoid a race where
      # the #stream_log_<id> target doesn't exist yet after a step transition.
      broadcast_step(run, run_step)
    }

    result = executor.execute(&on_progress)

    return result if result.passed? || step.max_retries.zero?

    (2..(step.max_retries + 1)).each do |attempt|
      run_step.update!(status: "retrying", attempt: attempt)
      broadcast_step(run, run_step)
      result = executor.execute(&on_progress)
      return result if result.passed?
    end

    result
  end

  def complete_step(run, run_step, step, result)
    attrs = {
      status: "passed",
      output: result.stdout,
      error_output: result.stderr,
      exit_code: result.exit_code,
      finished_at: Time.current,
      duration: Time.current - run_step.started_at
    }
    attrs[:stream_log] = result.stream_events if result.stream_events.present?
    run_step.update!(attrs)

    extract_context(run, step, result.stdout)
    capture_full_output(run, step, result.stdout)
    broadcast_step(run, run_step)
  end

  def fail_step(run, run_step, result)
    attrs = {
      status: "failed",
      output: result.stdout,
      error_output: result.stderr,
      exit_code: result.exit_code,
      finished_at: Time.current,
      duration: Time.current - run_step.started_at
    }
    attrs[:stream_log] = result.stream_events if result.stream_events.present?
    run_step.update!(attrs)
    broadcast_step(run, run_step)
  end

  def sync_task_status(run)
    task = run.pipeline_task
    return unless task

    task.update!(status: run.status == "completed" ? "completed" : "failed")
  end

  def extract_context(run, step, stdout)
    outputs = step.config["outputs"]
    return unless outputs

    extracted = ContextExtractor.new(outputs, stdout).extract
    run.update!(context: run.context.merge(extracted)) if extracted.any?
  end

  def capture_full_output(run, step, stdout)
    key = step.config["capture_output"]
    return if key.blank?

    run.update!(context: run.context.merge(key => stdout))
  end

  # --- Turbo Streams ---

  def broadcast_step(run, run_step)
    Turbo::StreamsChannel.broadcast_replace_to(
      run,
      target: "run_step_#{run_step.id}",
      partial: "runs/run_step",
      locals: { run_step: run_step, run: run }
    )
  end

  def broadcast_stream_log(run, run_step)
    Turbo::StreamsChannel.broadcast_replace_to(
      run,
      target: "stream_log_#{run_step.id}",
      partial: "runs/stream_log",
      locals: { run_step: run_step }
    )
  end

  def broadcast_run(run)
    Turbo::StreamsChannel.broadcast_replace_to(
      run,
      target: "run_header",
      partial: "runs/run_header",
      locals: { run: run }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      run,
      target: "run_info",
      partial: "runs/run_info",
      locals: { run: run }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      run,
      target: "run_context",
      partial: "runs/run_context",
      locals: { run: run }
    )
    # Broadcast the full step list to show injected steps
    Turbo::StreamsChannel.broadcast_replace_to(
      run,
      target: "run_steps_list",
      partial: "runs/run_steps_list",
      locals: { run: run }
    )
  end
end
