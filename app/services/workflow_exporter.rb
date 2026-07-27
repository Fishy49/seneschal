class WorkflowExporter
  FORMAT_VERSION = 1

  def initialize(workflow)
    @workflow = workflow
  end

  def call
    {
      seneschal_workflow_export: {
        version: FORMAT_VERSION,
        exported_at: Time.current.iso8601,
        source_project_name: @workflow.project.name,
        workflow: export_workflow,
        skills: export_skills,
        json_schemas: export_json_schemas
      }
    }
  end

  private

  def steps
    @steps ||= @workflow.steps.includes(:skill).order(:position).to_a
  end

  def referenced_skills
    @referenced_skills ||= steps.filter_map(&:skill).uniq
  end

  def referenced_schemas
    @referenced_schemas ||= begin
      from_steps = steps.filter_map(&:json_schema)
      from_skills = referenced_skills.filter_map(&:default_json_schema)
      (from_steps + from_skills).uniq
    end
  end

  def export_workflow
    {
      name: @workflow.name,
      description: @workflow.description,
      config: @workflow.config,
      steps: steps.map { |s| export_step(s) }
    }
  end

  def export_step(step)
    {
      name: step.name,
      position: step.position,
      step_type: step.step_type,
      body: step.body,
      config: export_step_config(step),
      skill_ref: skill_ref(step.skill),
      json_schema_ref: step.json_schema&.name,
      max_retries: step.max_retries,
      timeout: step.timeout,
      input_context: step.input_context,
      manual_approval: step.manual_approval
    }
  end

  # The raw config blob contains the json_schema_id (DB FK) and may carry
  # context_projects (FKs to other projects). Both are meaningless across
  # an export, so strip them; the schema is re-attached on import via the
  # symbolic json_schema_ref name.
  def export_step_config(step)
    cfg = (step.config || {}).dup
    cfg.delete("json_schema_id")
    cfg.delete("context_projects")
    cfg
  end

  def skill_ref(skill)
    return nil unless skill

    {
      scope: skill.shared? ? "shared" : "project",
      name: skill.name
    }
  end

  def export_skills
    referenced_skills.map { |s| export_skill(s) }
  end

  def export_skill(skill)
    {
      name: skill.name,
      scope: skill.shared? ? "shared" : "project",
      source_kind: skill.source_kind,
      relative_path: skill.relative_path,
      description: skill.description,
      default_json_schema_name: skill.default_json_schema&.name,
      default_output_variable: skill.default_output_variable,
      skill_md_content: read_skill_md(skill)
    }
  end

  def read_skill_md(skill)
    path = skill.skill_md_path
    return nil unless path && File.exist?(path)

    File.read(path)
  end

  def export_json_schemas
    referenced_schemas.map { |s| { name: s.name, description: s.description, body: s.body } }
  end
end
