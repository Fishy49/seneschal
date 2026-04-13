require "open3"

class ExecuteRunJob < ApplicationJob # rubocop:disable Metrics/ClassLength
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

    # Build the execution queue from workflow steps + any run-scoped ad-hoc steps.
    workflow_steps = run.workflow.steps.to_a
    ad_hoc_steps = run.ad_hoc_steps.to_a
    all_steps = workflow_steps + ad_hoc_steps
    queue = all_steps.map { |s| [s, nil] }

    if resume && resume_from_step_id.present?
      position = run.run_steps.maximum(:position) || 0
      queue.shift while queue.any? && queue.first[0].id != resume_from_step_id
      crashed_run_step = run.run_steps.where(step_id: resume_from_step_id, status: "failed").last
      queue[0] = [queue[0][0], crashed_run_step.id] if crashed_run_step && queue.any?
    elsif resume_from_step_id.present?
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
      resolved_context = resolve_input_context(step, run.context)

      if queued_run_step_id
        run_step = run.run_steps.find(queued_run_step_id)
        run_step.update!(status: "running", started_at: Time.current,
                         position: position, resolved_input_context: resolved_context)
      else
        run_step = run.run_steps.create!(step: step, status: "running", attempt: 1,
                                         position: position, started_at: Time.current,
                                         resolved_input_context: resolved_context)
      end
      broadcast_run(run)

      result = execute_with_retries(run, run_step, step, repo_path, resolved_context)

      if result.passed?
        mark_passed(run_step, result)

        extracted = PipelineExtractor.new(step, result.stdout).extract
        run.update!(context: run.context.merge(extracted)) if extracted.any?

        missing = step.produces - extracted.keys
        if missing.empty?
          broadcast_step(run, run_step)
          next
        end

        # Validation failed
        validation_msg = "Pipeline validation: step '#{step.name}' did not produce: #{missing.join(", ")}"
        run_step.update!(status: "failed", error_output: [run_step.error_output, validation_msg].compact.join("\n"))
        broadcast_step(run, run_step)
        result = StepExecutor::Result.new(exit_code: 1, stdout: result.stdout, stderr: validation_msg)
      else
        mark_failed(run_step, result)
      end

      # On-fail recovery: run a recovery action then re-execute the step
      on_fail = step.config["on_fail_action"]
      if on_fail.present? && on_fail["type"].present?
        recovered = attempt_recovery(run, run_step, step, on_fail, repo_path)
        if recovered
          broadcast_step(run, run_step)
          next
        end
      end

      run.update!(status: "failed", finished_at: Time.current, error_message: "Step '#{step.name}' failed")
      sync_task_status(run)
      broadcast_run(run)
      return
    end

    run.update!(status: "completed", finished_at: Time.current)
    sync_task_status(run)
    broadcast_run(run)
  end

  private

  # --- On-fail recovery loop ---

  def attempt_recovery(run, parent_run_step, step, on_fail, repo_path)
    max_rounds = on_fail.fetch("max_rounds", 3)

    return attempt_reopen_previous(run, parent_run_step, step, on_fail, repo_path, max_rounds) if on_fail["type"] == "reopen_previous"

    max_rounds.times do |i|
      round = i + 1
      run.reload
      return false if run.status == "stopped"

      # Inject failure context for the recovery action
      failure_output = [parent_run_step.output, parent_run_step.error_output].compact.join("\n")
      run.update!(context: run.context.merge(
        "previous_failure" => failure_output,
        "previous_failure_step" => step.name,
        "recovery_round" => round.to_s
      ))

      # Create an ad-hoc step for the recovery action
      recovery_step = run.ad_hoc_steps.create!(
        name: "#{step.name} - recovery (round #{round})",
        step_type: on_fail["type"],
        body: on_fail["body"],
        skill_id: on_fail["skill_id"],
        position: 0,
        config: on_fail.slice("model", "effort", "max_turns", "allowed_tools", "produces", "consumes")
      )

      # Execute recovery as a child step
      child_run_step = run.run_steps.create!(
        step: recovery_step,
        parent_run_step_id: parent_run_step.id,
        status: "running", attempt: 1, position: 0,
        started_at: Time.current
      )
      broadcast_run(run)

      scoped = scope_context(recovery_step, run.context)
      executor = StepExecutor.new(recovery_step, scoped, repo_path)
      recovery_result = executor.execute { |update| broadcast_child_progress(child_run_step, update) }

      if recovery_result.passed?
        mark_passed(child_run_step, recovery_result)

        extracted = PipelineExtractor.new(recovery_step, recovery_result.stdout).extract
        run.update!(context: run.context.merge(extracted)) if extracted.any?
      else
        mark_failed(child_run_step, recovery_result)
        broadcast_step(run, child_run_step)
        return false
      end
      broadcast_step(run, child_run_step)

      # Re-execute the original step
      parent_run_step.update!(status: "retrying", attempt: round + 1, started_at: Time.current)
      broadcast_step(run, parent_run_step)

      resolved_context = resolve_input_context(step, run.context)
      scoped = scope_context(step, run.context)
      executor = StepExecutor.new(step, scoped, repo_path, resolved_input_context: resolved_context)
      result = executor.execute { |update| broadcast_child_progress(parent_run_step, update) }

      if result.passed?
        mark_passed(parent_run_step, result)

        extracted = PipelineExtractor.new(step, result.stdout).extract
        run.update!(context: run.context.merge(extracted)) if extracted.any?

        missing = step.produces - extracted.keys
        return true if missing.empty?

        validation_msg = "Pipeline validation: step '#{step.name}' did not produce: #{missing.join(", ")}"
        parent_run_step.update!(status: "failed", error_output: [parent_run_step.error_output, validation_msg].compact.join("\n"))

      else
        mark_failed(parent_run_step, result)
      end
    end

    false
  end

  def attempt_reopen_previous(run, parent_run_step, step, on_fail, repo_path, max_rounds) # rubocop:disable Metrics/ParameterLists,Naming/PredicateMethod
    # Find the previous skill/prompt RunStep that has a Claude session to resume
    prev_run_step = run.run_steps
                       .where(parent_run_step_id: nil)
                       .where(position: ...parent_run_step.position)
                       .where.not(claude_session_id: nil)
                       .order(position: :desc)
                       .first

    unless prev_run_step&.claude_session_id
      Rails.logger.warn("reopen_previous: no resumable previous step found for '#{step.name}'")
      return false
    end

    prev_step = prev_run_step.step
    instructions = on_fail["instructions"].to_s

    max_rounds.times do |i|
      round = i + 1
      run.reload
      return false if run.status == "stopped"

      # Build the resume message from the verification failure
      failure_output = [parent_run_step.output, parent_run_step.error_output].compact.join("\n")
      resume_msg = "The next step in the pipeline (\"#{step.name}\") failed validation on your output.\n\n"
      resume_msg += "Failure details:\n```\n#{failure_output.truncate(10_000)}\n```\n\n"
      resume_msg += "#{instructions}\n\n" if instructions.present?
      resume_msg += "Please fix your output to address the failure above. "
      resume_msg += "Remember to include the output variables block at the end."

      # Create a child RunStep representing the resumed session
      child_run_step = run.run_steps.create!(
        step: prev_step,
        parent_run_step_id: parent_run_step.id,
        status: "running", attempt: round, position: 0,
        started_at: Time.current,
        claude_session_id: prev_run_step.claude_session_id
      )
      broadcast_run(run)

      # Resume the previous step's Claude session
      scoped = scope_context(prev_step, run.context)
      executor = StepExecutor.new(prev_step, scoped, repo_path,
                                  resume_session_id: prev_run_step.claude_session_id,
                                  resume_message: resume_msg)
      resume_result = executor.execute { |update| broadcast_child_progress(child_run_step, update) }

      if resume_result.passed?
        mark_passed(child_run_step, resume_result)

        # Update the session_id in case it changed
        prev_run_step.update!(claude_session_id: child_run_step.claude_session_id) if child_run_step.claude_session_id.present?

        # Re-extract pipeline variables from the resumed output
        extracted = PipelineExtractor.new(prev_step, resume_result.stdout).extract
        run.update!(context: run.context.merge(extracted)) if extracted.any?
      else
        mark_failed(child_run_step, resume_result)
        broadcast_step(run, child_run_step)
        return false
      end
      broadcast_step(run, child_run_step)

      # Re-execute the current (verification) step with updated context
      parent_run_step.update!(status: "retrying", attempt: round + 1, started_at: Time.current,
                              output: nil, error_output: nil)
      broadcast_step(run, parent_run_step)

      resolved_context = resolve_input_context(step, run.context)
      scoped = scope_context(step, run.context)
      executor = StepExecutor.new(step, scoped, repo_path, resolved_input_context: resolved_context)
      result = executor.execute { |update| broadcast_child_progress(parent_run_step, update) }

      if result.passed?
        mark_passed(parent_run_step, result)

        extracted = PipelineExtractor.new(step, result.stdout).extract
        run.update!(context: run.context.merge(extracted)) if extracted.any?

        missing = step.produces - extracted.keys
        return true if missing.empty?

        validation_msg = "Pipeline validation: step '#{step.name}' did not produce: #{missing.join(", ")}"
        parent_run_step.update!(status: "failed", error_output: [parent_run_step.error_output, validation_msg].compact.join("\n"))
      else
        mark_failed(parent_run_step, result)
      end
    end

    false
  end

  # --- Step lifecycle ---

  def mark_passed(run_step, result)
    attrs = {
      status: "passed", output: result.stdout, error_output: result.stderr,
      exit_code: result.exit_code, finished_at: Time.current,
      duration: Time.current - run_step.started_at
    }
    attrs[:stream_log] = result.stream_events if result.stream_events.present?
    run_step.update!(attrs)
  end

  def mark_failed(run_step, result)
    attrs = {
      status: "failed", output: result.stdout, error_output: result.stderr,
      exit_code: result.exit_code, finished_at: Time.current,
      duration: Time.current - run_step.started_at
    }
    attrs[:stream_log] = result.stream_events if result.stream_events.present?
    run_step.update!(attrs)
  end

  def sync_task_status(run)
    task = run.pipeline_task
    return unless task

    task.update!(status: run.status == "completed" ? "completed" : "failed")
  end

  # --- Execution ---

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
    resume_sid = run_step.claude_session_id if step.step_type.in?(["skill", "prompt"])

    scoped = scope_context(step, run.context)

    executor = StepExecutor.new(step, scoped, repo_path,
                                resolved_input_context: resolved_context,
                                resume_session_id: resume_sid)

    on_progress = lambda { |update|
      attrs = { updated_at: Time.current }
      attrs[:output] = update[:output] if update.key?(:output)
      attrs[:error_output] = update[:error_output] if update.key?(:error_output)
      attrs[:stream_log] = update[:stream_log] if update.key?(:stream_log)
      attrs[:claude_session_id] = update[:claude_session_id] if update[:claude_session_id].present?
      RunStep.where(id: run_step.id).update_all(attrs)
      run_step.reload
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

  def scope_context(step, full_context)
    return full_context if step.consumes.empty?

    allowed_keys = step.consumes + Step::GLOBAL_VARIABLES
    full_context.select { |k, _| allowed_keys.include?(k.to_s) }
  end

  # --- Broadcasts ---

  def broadcast_child_progress(run_step, update)
    attrs = { updated_at: Time.current }
    attrs[:output] = update[:output] if update.key?(:output)
    attrs[:error_output] = update[:error_output] if update.key?(:error_output)
    attrs[:stream_log] = update[:stream_log] if update.key?(:stream_log)
    attrs[:claude_session_id] = update[:claude_session_id] if update[:claude_session_id].present?
    RunStep.where(id: run_step.id).update_all(attrs)
  end

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
      run, target: "run_header",
           partial: "runs/run_header", locals: { run: run }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      run, target: "run_info",
           partial: "runs/run_info", locals: { run: run }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      run, target: "run_context",
           partial: "runs/run_context", locals: { run: run }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      run, target: "run_steps_list",
           partial: "runs/run_steps_list", locals: { run: run }
    )
  end
end
