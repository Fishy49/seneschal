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

    run.update!(status: "running", started_at: run.started_at || Time.current)
    run.update!(error_message: nil, finished_at: nil) if resume
    broadcast_run(run)
    repo_path = project.local_path

    system("git", "-C", repo_path, "pull", "--ff-only")

    # Build the execution queue from workflow steps (exclude inject-only steps)
    # Queue entries are [step, queued_run_step_id] tuples
    all_steps = run.workflow.steps.where(injectable_only: false).to_a
    queue = all_steps.map { |s| [s, nil] }
    injection_count = 0

    if resume && resume_from_step_id.present?
      # Resuming an existing run: skip steps already executed, pick up position counter
      position = run.run_steps.maximum(:position) || 0

      # Drop everything before the resume step from the queue
      while queue.any? && queue.first[0].id != resume_from_step_id
        queue.shift
      end
    elsif resume_from_step_id.present?
      # New run with skip: create skipped RunSteps for steps before the resume point
      position = 0
      while queue.any? && queue.first[0].id != resume_from_step_id
        step, _ = queue.shift
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
      return if run.reload.status == "stopped"

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
    return nil unless step.input_context.present?

    any_resolved = false
    resolved = step.input_context.gsub(/\$\{(\w+)\}/) do
      value = context[$1] || context[$1.to_sym]
      if value.present?
        any_resolved = true
        value
      else
        ""
      end
    end

    return nil unless any_resolved

    resolved = resolved.strip
    resolved.present? ? resolved : nil
  end

  def execute_with_retries(run, run_step, step, repo_path, resolved_context = nil)
    executor = StepExecutor.new(step, run.context, repo_path, resolved_input_context: resolved_context)

    on_progress = ->(update) {
      attrs = {}
      attrs[:output] = update[:output] if update.key?(:output)
      attrs[:error_output] = update[:error_output] if update.key?(:error_output)
      attrs[:stream_log] = update[:stream_log] if update.key?(:stream_log)
      RunStep.where(id: run_step.id).update_all(attrs) if attrs.any?
      run_step.reload
      broadcast_step(run, run_step)
    }

    result = executor.execute(&on_progress)

    return result if result.passed? || step.max_retries == 0

    (2..step.max_retries + 1).each do |attempt|
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
    broadcast_run(run)
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
    return unless key.present?

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
