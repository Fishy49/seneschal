class RunsController < ApplicationController
  before_action :set_run, only: [:show, :stop, :resume, :retry_from, :follow_up, :approve, :reject]

  def index
    @runs = Run.includes(:pipeline_task, workflow: :project).recent

    @runs = @runs.where(workflows: { project_id: params[:project_id] }) if params[:project_id].present?
    @runs = @runs.where(workflow_id: params[:workflow_id]) if params[:workflow_id].present?
    @runs = @runs.where(status: params[:status]) if params[:status].present?

    @runs = @runs.limit(50)
    @projects = Project.order(:name)
  end

  def show; end

  def stop
    if @run.active?
      @run.update!(status: "stopped", finished_at: Time.current, error_message: "Stopped by user")
      @run.pipeline_task&.update!(status: "failed")
    end
    redirect_to run_path(@run), notice: "Run stopped."
  end

  def resume
    unless @run.status.in?(["failed", "stopped"])
      redirect_to run_path(@run), alert: "Can only resume failed or stopped runs."
      return
    end

    failed_step = @run.run_steps.find_by(status: "failed")&.step
    unless failed_step
      redirect_to run_path(@run), alert: "No failed step to resume from."
      return
    end

    # Inject failure context so the injection logic can use it
    failed_run_step = @run.run_steps.find_by(status: "failed")
    failure_output = [failed_run_step.output, failed_run_step.error_output].compact.join("\n")
    @run.update!(context: @run.context.merge(
      "previous_failure" => failure_output.presence,
      "previous_failure_step" => failed_step.name
    ).compact)

    ExecuteRunJob.perform_later(@run, failed_step.id, resume: true)
    redirect_to run_path(@run), notice: "Resuming from '#{failed_step.name}'."
  end

  def follow_up
    unless @run.status.in?(["completed", "failed", "stopped"])
      redirect_to run_path(@run), alert: "Can only follow up on finished runs."
      return
    end

    instructions = params[:instructions].to_s.strip
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
    unless @run.awaiting_approval?
      redirect_to run_path(@run), alert: "Run is not awaiting approval." and return
    end

    awaiting = @run.awaiting_run_step
    unless awaiting
      redirect_to run_path(@run), alert: "No step awaiting approval." and return
    end

    awaiting.update!(status: "passed", rejection_context: nil)
    @run.update!(status: "running")
    ExecuteRunJob.perform_later(@run, awaiting.step_id, after_approval: true)
    redirect_to run_path(@run), notice: "Step approved. Continuing run."
  end

  def reject
    unless @run.awaiting_approval?
      redirect_to run_path(@run), alert: "Run is not awaiting approval." and return
    end

    awaiting = @run.awaiting_run_step
    unless awaiting
      redirect_to run_path(@run), alert: "No step awaiting approval." and return
    end

    context = params[:rejection_context].to_s.strip
    awaiting.update!(rejection_context: context.presence)
    @run.update!(status: "running")
    ExecuteRunJob.perform_later(@run, awaiting.step_id, resume: true)
    redirect_to run_path(@run), notice: "Step rejected. Re-running with feedback."
  end

  def retry_from
    step = @run.workflow.steps.find(params[:step_id])

    failure_context = @run.context.dup
    failed_run_step = @run.run_steps.find_by(status: "failed")
    if failed_run_step
      failure_output = [failed_run_step.output, failed_run_step.error_output].compact.join("\n")
      failure_context["previous_failure"] = failure_output if failure_output.present?
      failure_context["previous_failure_step"] = failed_run_step.step.name
    end

    new_run = @run.workflow.runs.create!(
      status: "pending",
      context: failure_context,
      input: @run.input.merge("resumed_from_run" => @run.id.to_s),
      pipeline_task: @run.pipeline_task
    )

    @run.pipeline_task&.update!(status: "running")

    ExecuteRunJob.perform_later(new_run, step.id)
    redirect_to run_path(new_run), notice: "Retrying from step '#{step.name}'."
  end

  private

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
    @run = Run.includes(workflow: :project, run_steps: :step).find(params[:id])
  end
end
