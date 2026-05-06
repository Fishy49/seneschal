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

  def available_variables
    vars = Step.available_variables_for(@workflow, params[:position].to_i)
               .map { |v| { name: v["name"], source: v["source"] } }
    render json: { variables: vars }
  end

  def reorder
    ids = params[:step_ids] || []
    ids.each_with_index do |id, index|
      step = @workflow.steps.find_by(id: id)
      step&.update!(position: index + 1)
    end
    head :ok
  end

  def move
    new_position = params[:position].to_i
    @step.update!(position: new_position)
    redirect_to project_workflow_path(@project, @workflow)
  end

  def produces_suggestions
    names = (Step::GLOBAL_VARIABLES + Step.pluck(:config).flat_map { |c| Array(c["produces"]) }).compact.uniq.sort
    render json: { suggestions: names }
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
      config: step.config.except("context_projects"),
      skill_id: step.skill_id,
      max_retries: step.max_retries,
      timeout: step.timeout,
      input_context: step.input_context,
      manual_approval: step.manual_approval
    )
  end

  def step_params
    permitted = params.expect(step: [:name, :position, :step_type, :max_retries, :timeout, :config, :skill_id, :body,
                                     :input_context, :manual_approval]).to_h

    raw = request.params
    permitted[:config] = build_step_config(permitted[:step_type], raw)

    # Pipeline: produces and consumes
    produces =
      if claude_schema_mode?(permitted)
        [raw["schema_output_variable"].to_s.strip].compact_blank
      else
        raw["produces"].to_s.split(",").map(&:strip).compact_blank
      end
    consumes = Array(raw["consumes"]).compact_blank
    if permitted[:step_type] == "json_validator" && raw["json_validator_source_variable"].present?
      consumes << raw["json_validator_source_variable"].to_s.strip
      consumes.uniq!
    end
    permitted[:config]["produces"] = produces if produces.any?
    permitted[:config]["consumes"] = consumes if consumes.any?

    # On-fail recovery action
    if raw["on_fail_type"].present?
      on_fail = { "type" => raw["on_fail_type"], "max_rounds" => (raw["on_fail_max_rounds"].presence || 3).to_i }
      on_fail["skill_id"] = raw["on_fail_skill_id"].to_i if raw["on_fail_skill_id"].present?
      on_fail["body"] = raw["on_fail_body"] if raw["on_fail_body"].present?
      on_fail["instructions"] = raw["on_fail_instructions"] if raw["on_fail_instructions"].present?
      permitted[:config]["on_fail_action"] = on_fail
    end

    permitted
  end

  def claude_schema_mode?(permitted)
    permitted[:step_type].to_s.in?(["skill", "prompt"]) &&
      permitted[:config]["json_schema_id"].present?
  end

  def build_step_config(step_type, raw)
    case step_type
    when "ci_check" then build_ci_check_config(raw)
    when "skill", "prompt" then build_skill_config(raw)
    when "context_fetch" then build_context_fetch_config(raw)
    when "json_validator" then build_json_validator_config(raw)
    else {}
    end
  end

  def build_ci_check_config(raw)
    {
      "mode" => raw["ci_mode"] || "pr",
      "pr" => raw["ci_pr"].presence,
      "workflow" => raw["ci_workflow"].presence,
      "ref" => raw["ci_ref"].presence,
      "trigger" => raw["ci_trigger"] == "1",
      "poll_interval" => (raw["ci_poll_interval"].presence || 30).to_i,
      "max_log_chars" => (raw["ci_max_log_chars"].presence || 10_000).to_i,
      "log_from" => raw["ci_log_from"].presence || "end"
    }.compact
  end

  def build_skill_config(raw)
    config = {}
    config["effort"] = raw["skill_effort"].presence || "medium"
    config["model"] = raw["skill_model"] if raw["skill_model"].present?
    config["max_turns"] = raw["skill_max_turns"].to_i if raw["skill_max_turns"].present?
    config["allowed_tools"] = raw["skill_allowed_tools"] if raw["skill_allowed_tools"].present?
    config["json_schema_id"] = raw["json_schema_id"].to_i if raw["json_schema_id"].present?

    context_ids = Array(raw["skill_context_projects"]).compact_blank.map(&:to_i).uniq
    config["context_projects"] = context_ids if context_ids.any?

    config
  end

  def build_json_validator_config(raw)
    {
      "json_schema_id" => raw["json_validator_schema_id"].presence&.to_i,
      "source_variable" => raw["json_validator_source_variable"].to_s.strip.presence
    }.compact
  end

  def build_context_fetch_config(raw)
    {
      "method" => raw["fetch_method"].presence || "url",
      "url" => raw["fetch_url"].presence,
      "context_key" => raw["fetch_context_key"].presence,
      "capture_output" => raw["fetch_context_key"].presence
    }.compact
  end
end
