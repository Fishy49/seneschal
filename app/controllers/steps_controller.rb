class StepsController < ApplicationController
  before_action :set_project_and_workflow
  before_action :set_step, only: [:edit, :update, :destroy, :move]

  def new
    next_position = (@workflow.steps.maximum(:position) || 0) + 1
    @step = @workflow.steps.build(position: next_position)
  end

  def edit; end

  def create
    @step = @workflow.steps.build(step_params)
    if @step.save
      save_as_template(@step)
      redirect_to project_workflow_path(@project, @workflow), notice: "Step added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @step.update(step_params)
      save_as_template(@step)
      redirect_to project_workflow_path(@project, @workflow), notice: "Step updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @step.destroy
    redirect_to project_workflow_path(@project, @workflow), notice: "Step removed."
  end

  def move
    new_position = params[:position].to_i
    @step.update!(position: new_position)
    redirect_to project_workflow_path(@project, @workflow)
  end

  private

  def set_project_and_workflow
    @project = Project.find(params[:project_id])
    @workflow = @project.workflows.find(params[:workflow_id])
  end

  def set_step
    @step = @workflow.steps.find(params[:id])
  end

  def save_as_template(step)
    return unless params[:save_as_template] == "1" && params[:template_name].present?

    StepTemplate.create(
      name: params[:template_name],
      step_type: step.step_type,
      body: step.body,
      config: step.config,
      skill_id: step.skill_id,
      max_retries: step.max_retries,
      timeout: step.timeout,
      input_context: step.input_context,
      injectable_only: step.injectable_only
    )
  end

  def step_params
    permitted = params.expect(step: [:name, :position, :step_type, :max_retries, :timeout, :config, :skill_id, :body, :input_context,
                                     :injectable_only]).to_h

    # Use raw request params for config fields that live outside the step namespace
    raw = request.params

    case permitted[:step_type]
    when "ci_check"
      permitted[:config] = {
        "mode" => raw["ci_mode"] || "pr",
        "pr" => raw["ci_pr"].presence,
        "workflow" => raw["ci_workflow"].presence,
        "ref" => raw["ci_ref"].presence,
        "trigger" => raw["ci_trigger"] == "1",
        "poll_interval" => (raw["ci_poll_interval"].presence || 30).to_i
      }.compact
    when "skill"
      config = {}
      config["model"] = raw["skill_model"] if raw["skill_model"].present?
      config["max_turns"] = raw["skill_max_turns"].to_i if raw["skill_max_turns"].present?
      config["capture_output"] = raw["skill_capture_output"] if raw["skill_capture_output"].present?
      config["outputs"] = begin; JSON.parse(raw["skill_outputs"]); rescue StandardError; {}; end if raw["skill_outputs"].present?
      config["allowed_tools"] = raw["skill_allowed_tools"] if raw["skill_allowed_tools"].present?
      permitted[:config] = config
    else
      permitted[:config] = {}
    end

    # Merge on_failure_inject config (available for all step types)
    inject_steps = Array(raw["on_failure_inject"]).compact_blank
    if inject_steps.any?
      permitted[:config] = permitted[:config].merge(
        "on_failure_inject" => inject_steps,
        "max_injections" => (raw["max_injections"].presence || 3).to_i
      )
    end

    permitted
  end
end
