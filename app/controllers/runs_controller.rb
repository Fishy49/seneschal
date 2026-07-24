class RunsController < ApplicationController
  before_action :set_run, only: [:show, :stop, :resume, :retry_from, :follow_up, :approve, :reject, :replay, :diff]

  def index
    @runs = Run.includes(:pipeline_task, workflow: :project).recent

    @runs = @runs.where(workflows: { project_id: params[:project_id] }) if params[:project_id].present?
    @runs = @runs.where(workflow_id: params[:workflow_id]) if params[:workflow_id].present?
    @runs = @runs.where(status: params[:status]) if params[:status].present?

    @runs = @runs.limit(50)
    @projects = Project.order(:name)
  end

  def show; end

  # Trajectory replay: a richer, drill-down view of a single Run's full
  # stream_log across all its RunSteps. Static (no live polling) so it
  # works equally well on completed runs as on still-running ones.
  def replay
    @run_steps = @run.run_steps.includes(:step).where(parent_run_step_id: nil).order(:position)
  end

  # Side-by-side diff of two Runs. The "other" Run is picked from the same
  # PipelineTask by default (most useful — same task, different runs) but
  # any other run of the same Workflow is accepted too. Diff alignment is
  # by RunStep position; per-step trajectory entries are compared via
  # `trajectory_signature` so cost/timing drift doesn't show up as a diff.
  def diff
    @against = pick_diff_target(params[:against])
    @available_targets = candidate_diff_targets

    if @against.nil?
      flash.now[:alert] = "Pick another Run to diff against."
      return
    end

    @left_steps = @run.run_steps.includes(:step).where(parent_run_step_id: nil).order(:position)
    @right_steps = @against.run_steps.includes(:step).where(parent_run_step_id: nil).order(:position)
  end

  def stop
    if @run.active?
      @run.update!(status: "stopped", finished_at: Time.current,
                   stopped_by: current_user,
                   error_message: "Stopped by #{current_user.email}")
      @run.pipeline_task&.update!(status: "failed")
      Event.record("run.stopped", subject: @run, user: current_user)
    end
    redirect_to run_path(@run), notice: "Run stopped."
  end

  def resume
    unless @run.status.in?(["failed", "stopped", "waiting_for_tokens"])
      redirect_to run_path(@run), alert: "Can only resume failed, stopped, or waiting runs."
      return
    end

    resumable_run_step = @run.run_steps.find_by(status: ["failed", "waiting_for_tokens"])
    unless resumable_run_step
      redirect_to run_path(@run), alert: "No failed or waiting step to resume from."
      return
    end

    resumable_step = resumable_run_step.step
    failure_output = [resumable_run_step.output, resumable_run_step.error_output].compact.join("\n")
    @run.update!(context: @run.context.merge(
      "previous_failure" => failure_output.presence,
      "previous_failure_step" => resumable_step.name
    ).compact)

    ExecuteRunJob.perform_later(@run, resumable_step.id, resume: true)
    redirect_to run_path(@run), notice: "Resuming from '#{resumable_step.name}'."
  end

  def follow_up
    unless @run.status.in?(["completed", "failed", "stopped"])
      redirect_to run_path(@run), alert: "Can only follow up on finished runs."
      return
    end

    instructions = params.expect(:instructions).to_s.strip
    if instructions.blank?
      redirect_to run_path(@run), alert: "Follow-up instructions are required."
      return
    end

    prompt_step = build_follow_up_steps(instructions, Array(params[:skill_ids]).compact_blank)

    @run.update!(status: "running", finished_at: nil, error_message: nil)
    @run.pipeline_task&.update!(status: "running")

    ExecuteRunJob.perform_later(@run, prompt_step.id, resume: true)
    redirect_to run_path(@run), notice: "Follow-up running."
  end

  def approve
    return redirect_to run_path(@run), alert: already_decided_alert unless @run.awaiting_approval?

    awaiting = @run.awaiting_run_step
    return redirect_to run_path(@run), alert: "No step awaiting approval." unless awaiting

    awaiting.approval_events.create!(user: current_user, action: "approved",
                                     comment: params[:comment].to_s.strip.presence)
    # The clear stays: ExecuteRunJob keys re-injection off rejection_context.
    # The human-readable record is the approval event created above.
    awaiting.update!(status: "passed", rejection_context: nil)
    Event.record("run.approved", subject: @run, user: current_user, metadata: { "step" => awaiting.step&.name })
    @run.update!(status: "running")
    ExecuteRunJob.perform_later(@run, awaiting.step_id, after_approval: true)
    redirect_to run_path(@run), notice: "Step approved. Continuing run."
  end

  def reject
    return redirect_to run_path(@run), alert: already_decided_alert unless @run.awaiting_approval?

    awaiting = @run.awaiting_run_step
    return redirect_to run_path(@run), alert: "No step awaiting approval." unless awaiting

    context = params.expect(:rejection_context).to_s.strip
    awaiting.approval_events.create!(user: current_user, action: "rejected", comment: context.presence)
    awaiting.update!(rejection_context: context.presence)
    Event.record("run.rejected", subject: @run, user: current_user, metadata: { "step" => awaiting.step&.name })
    @run.update!(status: "running")
    ExecuteRunJob.perform_later(@run, awaiting.step_id, resume: true)
    redirect_to run_path(@run), notice: "Step rejected. Re-running with feedback."
  end

  def retry_from
    step = @run.workflow.steps.find(params.expect(:step_id))

    failure_context = @run.context.dup
    failed_run_step = @run.run_steps.find_by(status: ["failed", "waiting_for_tokens"])
    if failed_run_step
      failure_output = [failed_run_step.output, failed_run_step.error_output].compact.join("\n")
      failure_context["previous_failure"] = failure_output if failure_output.present?
      failure_context["previous_failure_step"] = failed_run_step.step.name
    end

    new_run = @run.workflow.runs.create!(
      status: "pending",
      context: failure_context,
      input: @run.input.merge("resumed_from_run" => @run.id.to_s),
      pipeline_task: @run.pipeline_task,
      started_by: current_user
    )

    @run.pipeline_task&.update!(status: "running")
    Event.record("run.started", subject: new_run, user: current_user)

    ExecuteRunJob.perform_later(new_run, step.id)
    redirect_to run_path(new_run), notice: "Retrying from step '#{step.name}'."
  end

  private

  # Two people can be looking at the same parked run. Name whoever decided
  # first instead of a bare "not awaiting approval".
  def already_decided_alert
    event = @run.latest_approval_event
    return "Run is not awaiting approval." unless event

    "Already #{event.action} by #{event.actor_label}."
  end

  def build_follow_up_steps(instructions, skill_ids)
    ActiveRecord::Base.transaction do
      position = @run.ad_hoc_steps.maximum(:position) || @run.workflow.steps.maximum(:position) || 0

      position += 1
      prompt_step = @run.ad_hoc_steps.create!(
        name: "Follow Up", step_type: "prompt", position: position,
        body: instructions, config: { "effort" => "medium" },
        max_retries: 0, timeout: 1800
      )

      skill_ids.each do |skill_id|
        skill = Skill.for_project(@run.workflow.project).find_by(id: skill_id)
        next unless skill

        position += 1
        @run.ad_hoc_steps.create!(
          name: skill.name, step_type: "skill", position: position,
          skill: skill, config: { "effort" => "medium" },
          max_retries: 0, timeout: 1800
        )
      end

      prompt_step
    end
  end

  def set_run
    @run = Run.includes(workflow: :project, run_steps: :step).find(params.expect(:id))
  end

  # Candidate diff targets, ordered most-useful first:
  #   1. Other runs of the same PipelineTask (apples-to-apples — same task,
  #      different attempts)
  #   2. Other runs of the same Workflow (next-best — same pipeline, may
  #      differ on input)
  # `current_run` is excluded; the list is limited to a sensible UI cap.
  def candidate_diff_targets
    base = Run.where.not(id: @run.id).order(created_at: :desc)
    if @run.pipeline_task_id
      base.where(pipeline_task_id: @run.pipeline_task_id).limit(20)
    else
      base.where(workflow_id: @run.workflow_id).limit(20)
    end
  end

  def pick_diff_target(against_id)
    return candidate_diff_targets.first if against_id.blank?

    candidate_diff_targets.find_by(id: against_id)
  end
end
