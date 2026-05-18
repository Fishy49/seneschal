class DataImporter
  attr_reader :stats

  def initialize(data)
    @data = data.deep_symbolize_keys[:seneschal_export]
    @skill_map = {}
    @group_map = {}
    @schema_map = {}
    @stats = Hash.new(0)
  end

  def call
    validate!
    ActiveRecord::Base.transaction do
      wipe!
      import_project_groups
      import_json_schemas
      import_skills
      import_projects
      import_step_templates
    end
    stats
  end

  private

  def validate!
    raise ArgumentError, "Invalid export file: missing seneschal_export key" unless @data
    raise ArgumentError, "Unsupported export version" unless @data[:version] == 1
  end

  def wipe!
    RunStep.delete_all
    Run.delete_all
    PipelineTask.delete_all
    Step.delete_all
    StepTemplate.delete_all
    Workflow.delete_all
    Skill.delete_all
    Project.delete_all
    ProjectGroup.delete_all
    JsonSchema.delete_all
  end

  def import_json_schemas
    (@data[:json_schemas] || []).each do |attrs|
      schema = JsonSchema.create!(
        name: attrs[:name],
        description: attrs[:description],
        body: attrs[:body]
      )
      @schema_map[attrs[:name]] = schema
      @stats[:json_schemas] += 1
    end
  end

  def import_project_groups
    (@data[:project_groups] || []).each do |attrs|
      group = ProjectGroup.create!(
        name: attrs[:name],
        description: attrs[:description]
      )
      @group_map[attrs[:name]] = group
      @stats[:project_groups] += 1
    end
  end

  def import_skills
    (@data[:skills] || []).each do |attrs|
      next if attrs[:project_name].present?

      build_skill_from_attrs(attrs, project: nil)
      @stats[:skills] += 1
    end
  end

  def import_projects
    (@data[:projects] || []).each do |proj_attrs|
      project = Project.new(
        name: proj_attrs[:name],
        repo_url: proj_attrs[:repo_url],
        local_path: proj_attrs[:local_path],
        description: proj_attrs[:description],
        markdown_context: proj_attrs[:markdown_context],
        project_group: @group_map[proj_attrs[:project_group_name]],
        skip_permissions: proj_attrs[:skip_permissions] || false,
        repo_status: "not_cloned"
      )
      project.save!(validate: false)
      @stats[:projects] += 1

      import_project_skills(project)

      workflow_map = {}
      (proj_attrs[:workflows] || []).each do |wf_attrs|
        workflow = import_workflow(project, wf_attrs)
        workflow_map[wf_attrs[:name]] = workflow
      end

      (proj_attrs[:tasks] || []).each do |task_attrs|
        import_task(project, workflow_map, task_attrs)
      end
    end
  end

  def import_project_skills(project)
    (@data[:skills] || []).each do |attrs|
      next unless attrs[:project_name] == project.name

      build_skill_from_attrs(attrs, project: project)
      @stats[:skills] += 1
    end
  end

  # Translates one Skill payload into an AR row + (optional) materialized
  # SKILL.md on disk. Honors `source_kind`/`relative_path` from the export so
  # the imported row resolves to the same on-disk path. When the export
  # bundled the SKILL.md content via `skill_md_content`, this method writes
  # it back so the imported install is self-contained even if the project
  # repo isn't cloned locally yet.
  def build_skill_from_attrs(attrs, project:)
    skill = Skill.create!(
      name: attrs[:name],
      description: attrs[:description],
      project: project,
      source_kind: attrs[:source_kind],
      relative_path: attrs[:relative_path]
    )

    materialize_skill_md(skill, attrs[:skill_md_content])
    skill.refresh_cached_metadata!
    @skill_map[skill_key(project&.name, attrs[:name])] = skill
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

  def import_workflow(project, wf_attrs)
    workflow = project.workflows.create!(
      name: wf_attrs[:name],
      description: wf_attrs[:description],
      trigger_type: wf_attrs[:trigger_type] || "manual",
      trigger_config: wf_attrs[:trigger_config]
    )
    @stats[:workflows] += 1

    (wf_attrs[:steps] || []).each do |step_attrs|
      import_step(workflow, step_attrs)
    end

    workflow
  end

  def import_step(workflow, attrs)
    skill = find_skill(attrs[:skill_project_name], attrs[:skill_name])
    config = (attrs[:config] || {}).dup
    if attrs[:json_schema_name].present? && (schema = @schema_map[attrs[:json_schema_name]])
      config = config.merge("json_schema_id" => schema.id)
    end
    workflow.steps.create!(
      name: attrs[:name],
      position: attrs[:position],
      step_type: attrs[:step_type],
      body: attrs[:body],
      config: config,
      skill: skill,
      max_retries: attrs[:max_retries] || 0,
      timeout: attrs[:timeout] || 600,
      input_context: attrs[:input_context]
    )
    @stats[:steps] += 1
  end

  def import_task(project, workflow_map, attrs)
    workflow = workflow_map[attrs[:workflow_name]]
    status = attrs[:status] || "draft"
    status = "draft" if workflow.nil? && status != "draft"

    project.pipeline_tasks.create!(
      title: attrs[:title],
      body: attrs[:body],
      kind: attrs[:kind] || "feature",
      status: status,
      workflow: workflow
    )
    @stats[:tasks] += 1
  end

  def import_step_templates
    (@data[:step_templates] || []).each do |attrs|
      skill = find_skill(attrs[:skill_project_name], attrs[:skill_name])
      StepTemplate.create!(
        name: attrs[:name],
        step_type: attrs[:step_type],
        body: attrs[:body],
        config: attrs[:config] || {},
        skill: skill,
        max_retries: attrs[:max_retries] || 0,
        timeout: attrs[:timeout] || 600,
        input_context: attrs[:input_context]
      )
      @stats[:step_templates] += 1
    end
  end

  def find_skill(project_name, skill_name)
    return nil unless skill_name

    @skill_map[skill_key(project_name, skill_name)]
  end

  def skill_key(project_name, skill_name)
    "#{project_name || "shared"}:#{skill_name}"
  end
end
