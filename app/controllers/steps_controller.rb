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
    vars = Step.available_variables_for(@workflow, params.expect(:position).to_i)
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
    new_position = params.expect(:position).to_i
    @step.update!(position: new_position)
    redirect_to project_workflow_path(@project, @workflow)
  end

  def produces_suggestions
    names = (Step::GLOBAL_VARIABLES + Step.pluck(:config).flat_map { |c| Array(c["produces"]) }).compact.uniq.sort
    render json: { suggestions: names }
  end

  private

  def set_project_and_workflow
    @project = Project.find(params.expect(:project_id))
    @workflow = @project.workflows.find(params.expect(:workflow_id))
  end

  def set_step
    @step = @workflow.steps.find(params.expect(:id))
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
    permitted[:config] = build_step_config(permitted[:step_type], raw, permitted[:skill_id])

    # Pipeline: produces and consumes
    produces =
      if claude_schema_mode?(permitted, raw)
        [raw["schema_output_variable"].to_s.strip].compact_blank
      else
        raw["produces"].to_s.split(",").map(&:strip).compact_blank
      end
    consumes = Array(raw["consumes"]).compact_blank
    queries = Array(raw["queries"]).compact_blank
    permitted[:config]["produces"] = produces if produces.any?
    permitted[:config]["consumes"] = consumes if consumes.any?
    permitted[:config]["queries"] = queries if queries.any?

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

  # Schema mode is on whenever the form's schema-output single-input is the
  # canonical produces source — i.e. EITHER the step has an explicit
  # json_schema_id OR the form is in inherit mode (the "From skill" badge is
  # showing). Inherit mode used to fall through to the multi-tag widget here,
  # which silently wiped produces on every edit save.
  def claude_schema_mode?(permitted, raw)
    return false unless permitted[:step_type].to_s.in?(["skill", "prompt"])
    return true if permitted[:config]["json_schema_id"].present?

    raw["schema_picker_mode"] == "inherit"
  end

  def build_step_config(step_type, raw, skill_id = nil)
    case step_type
    when "ci_check" then build_ci_check_config(raw)
    when "skill", "prompt" then build_skill_config(raw, skill_id)
    when "context_fetch" then build_context_fetch_config(raw)
    when "pr" then build_pr_config(raw)
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

  def build_skill_config(raw, skill_id = nil)
    config = {}
    config["effort"] = raw["skill_effort"].presence || "medium"
    config["model"] = raw["skill_model"] if raw["skill_model"].present?
    config["max_turns"] = raw["skill_max_turns"].to_i if raw["skill_max_turns"].present?
    config["allowed_tools"] = raw["skill_allowed_tools"] if raw["skill_allowed_tools"].present?
    config["preview_assets"] = raw["skill_preview_assets"] == "1"

    # Schema picker has three persisted shapes (see app/views/steps/_form.html.erb):
    #   "inherit"  → resolve through skill.default_json_schema_id and persist
    #                the id explicitly. Step#inherit_skill_defaults only runs
    #                on new records / skill changes, so leaving the key absent
    #                on a normal edit drops the saved schema id on the floor.
    #   "override" → write whatever the picker has, even if blank — explicit
    #                "None" must beat inheritance.
    #   (legacy)   → schema_picker_mode missing, fall back to the picker value.
    case raw["schema_picker_mode"]
    when "inherit"
      default_id = Skill.where(id: skill_id).pick(:default_json_schema_id) if skill_id.present?
      config["json_schema_id"] = default_id if default_id.present?
    when "override"
      config["json_schema_id"] = raw["json_schema_id"].presence&.to_i
    else
      config["json_schema_id"] = raw["json_schema_id"].to_i if raw["json_schema_id"].present?
    end

    context_ids = Array(raw["skill_context_projects"]).compact_blank.map(&:to_i).uniq
    config["context_projects"] = context_ids if context_ids.any?

    config
  end

  def build_pr_config(raw)
    cfg = {
      "title" => raw["pr_title"].to_s.strip.presence,
      "body" => raw["pr_body"].to_s.presence,
      "base" => raw["pr_base"].to_s.strip.presence || "main",
      "draft" => raw["pr_draft"] != "0",
      "branch" => raw["pr_branch"].to_s.strip.presence,
      "reviewers" => split_csv(raw["pr_reviewers"]),
      "labels" => split_csv(raw["pr_labels"]),
      "assignees" => split_csv(raw["pr_assignees"]),
      # Destructive re-create. Default false so the idempotent reuse path
      # stays the easy default; operators have to opt in explicitly.
      "clean" => raw["pr_clean"] == "1"
    }
    # Strip nil + empty values without clobbering `draft: false` or `clean: false`.
    cfg.reject { |_, v| v.nil? || v == "" || (v.respond_to?(:empty?) && v.empty?) }
  end

  def split_csv(value)
    value.to_s.split(",").map(&:strip).compact_blank
  end

  def build_context_fetch_config(raw)
    method = raw["fetch_method"].presence || "url"
    cfg = {
      "method" => method,
      "context_key" => raw["fetch_context_key"].presence,
      "capture_output" => raw["fetch_context_key"].presence
    }
    case method
    when "url"
      cfg["url"] = raw["fetch_url"].presence
    when "project_file"
      cfg["path"] = raw["fetch_path"].presence
      cfg["json_schema_id"] = raw["fetch_json_schema_id"].to_i if raw["fetch_json_schema_id"].present?
    end
    cfg.compact
  end
end
