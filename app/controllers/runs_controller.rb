class RunsController < ApplicationController
  before_action :set_run, only: [:show, :stop, :resume, :retry_from, :follow_up]

  def index
    @runs = Run.includes(workflow: :project).recent

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
    instructions = params[:instructions].to_s.strip
    if instructions.blank?
      redirect_to run_path(@run), alert: "Follow-up instructions are required."
      return
    end

    follow_up_context = @run.context.merge(
      "follow_up_instructions" => instructions,
      "follow_up_from_run" => @run.id.to_s
    )

    new_run = @run.workflow.runs.create!(
      status: "pending",
      context: follow_up_context,
      input: @run.input.merge("follow_up_from_run" => @run.id.to_s)
    )

    ExecuteRunJob.perform_later(new_run)
    redirect_to run_path(new_run), notice: "Follow-up run started."
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

  def set_run
    @run = Run.includes(workflow: :project, run_steps: :step).find(params[:id])
  end
end
