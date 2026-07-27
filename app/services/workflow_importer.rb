class WorkflowImporter
  Result = Data.define(:workflow, :mode, :created_skills, :created_schemas, :missing_skills)

  # mode:
  #   :new      -> create a brand-new workflow in target_project. `name_override`
  #                is honored if given; otherwise a unique name is derived from
  #                the export's workflow name (with "(import N)" suffix when needed).
  #   :replace  -> replace the steps of `replace_workflow` (which must belong to
  #                target_project). The workflow row is updated in place
  #                (description, trigger, config) and its steps are rebuilt from
  #                the export. Existing runs/tasks are untouched.
  def initialize(data, target_project:, mode: :new, name_override: nil, replace_workflow: nil)
    @payload = data.deep_symbolize_keys[:seneschal_workflow_export]
    @target = target_project
    @mode = mode
    @name_override = name_override.presence
    @replace_workflow = replace_workflow

    @schema_map = {}
    @skill_map = {}
    @created_skills = []
    @created_schemas = []
    @missing_skills = []
  end

  def call
    validate!

    workflow = ActiveRecord::Base.transaction do
      import_json_schemas
      import_skills

      wf = case @mode
           when :new     then create_new_workflow
           when :replace then replace_existing_workflow
           else raise ArgumentError, "Unknown import mode: #{@mode.inspect}"
           end

      build_steps(wf)
      wf
    end

    Result.new(
      workflow: workflow,
      mode: @mode,
      created_skills: @created_skills,
      created_schemas: @created_schemas,
      missing_skills: @missing_skills
    )
  end

  private

  def validate!
    raise ArgumentError, "Invalid workflow export: missing seneschal_workflow_export key" unless @payload
    raise ArgumentError, "Unsupported workflow export version" unless @payload[:version] == WorkflowExporter::FORMAT_VERSION
    raise ArgumentError, "Export is missing a workflow" unless @payload[:workflow].is_a?(Hash)

    return unless @mode == :replace

    raise ArgumentError, "Replace mode requires an existing workflow" unless @replace_workflow
    raise ArgumentError, "Replace target must belong to the chosen project" unless @replace_workflow.project_id == @target.id
  end

  # JsonSchema names are globally unique. Reuse a same-named row if present,
  # otherwise create from the export. We don't overwrite an existing schema's
  # body — that would silently change unrelated workflows.
  def import_json_schemas
    Array(@payload[:json_schemas]).each do |attrs|
      existing = JsonSchema.find_by(name: attrs[:name])
      if existing
        @schema_map[attrs[:name]] = existing
      else
        schema = JsonSchema.create!(name: attrs[:name], description: attrs[:description], body: attrs[:body])
        @schema_map[attrs[:name]] = schema
        @created_schemas << schema
      end
    end
  end

  def import_skills
    Array(@payload[:skills]).each do |attrs|
      skill = resolve_or_create_skill(attrs)
      @skill_map[skill_key(attrs[:scope], attrs[:name])] = skill if skill
    end
  end

  # Resolution order:
  #   - shared skill: reuse Skill where project_id IS NULL and name matches;
  #     otherwise create as shared.
  #   - project skill: reuse @target.skills.find_by(name:) if present;
  #     otherwise create in the target project (with SKILL.md materialized
  #     when the export bundled the content).
  def resolve_or_create_skill(attrs)
    if attrs[:scope].to_s == "shared"
      existing = Skill.shared.find_by(name: attrs[:name])
      return existing if existing

      build_skill(attrs, project: nil)
    else
      existing = @target.skills.find_by(name: attrs[:name])
      return existing if existing

      build_skill(attrs, project: @target)
    end
  end

  def build_skill(attrs, project:)
    skill = Skill.create!(
      name: attrs[:name],
      description: attrs[:description],
      project: project,
      source_kind: attrs[:source_kind],
      relative_path: attrs[:relative_path],
      default_output_variable: attrs[:default_output_variable].presence,
      default_json_schema: @schema_map[attrs[:default_json_schema_name]]
    )
    materialize_skill_md(skill, attrs[:skill_md_content])
    skill.refresh_cached_metadata!
    @created_skills << skill
    skill
  end

  def materialize_skill_md(skill, content)
    return if content.blank?

    path = skill.skill_md_path
    return if path.nil?
    return if File.exist?(path)

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def create_new_workflow
    wf_attrs = @payload[:workflow]
    @target.workflows.create!(
      name: chosen_name(wf_attrs[:name]),
      description: wf_attrs[:description],
      config: wf_attrs[:config] || {}
    )
  end

  def replace_existing_workflow
    wf_attrs = @payload[:workflow]
    @replace_workflow.steps.destroy_all
    @replace_workflow.update!(
      description: wf_attrs[:description],
      config: wf_attrs[:config] || {}
    )
    @replace_workflow
  end

  def build_steps(workflow)
    Array(@payload[:workflow][:steps]).each do |step_attrs|
      skill = resolve_step_skill(step_attrs[:skill_ref])
      config = (step_attrs[:config] || {}).dup
      if step_attrs[:json_schema_ref].present? && (schema = @schema_map[step_attrs[:json_schema_ref]])
        config["json_schema_id"] = schema.id
      end

      workflow.steps.create!(
        name: step_attrs[:name],
        position: step_attrs[:position],
        step_type: step_attrs[:step_type],
        body: step_attrs[:body],
        config: config,
        skill: skill,
        max_retries: step_attrs[:max_retries] || 0,
        timeout: step_attrs[:timeout] || 600,
        input_context: step_attrs[:input_context],
        manual_approval: step_attrs[:manual_approval] || false
      )
    end
  end

  def resolve_step_skill(ref)
    return nil unless ref.is_a?(Hash)

    skill = @skill_map[skill_key(ref[:scope], ref[:name])]
    @missing_skills << ref[:name] if skill.nil?
    skill
  end

  def skill_key(scope, name)
    "#{scope || "shared"}:#{name}"
  end

  def chosen_name(default_name)
    return unique_name(@name_override) if @name_override

    unique_name(default_name)
  end

  def unique_name(base_name)
    return base_name unless @target.workflows.exists?(name: base_name)

    n = 2
    loop do
      candidate = "#{base_name} (import #{n})"
      return candidate unless @target.workflows.exists?(name: candidate)

      n += 1
    end
  end
end
