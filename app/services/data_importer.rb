class DataImporter
  attr_reader :stats

  def initialize(data)
    @data = data.deep_symbolize_keys[:seneschal_export]
    @skill_map = {}
    @stats = Hash.new(0)
  end

  def call
    validate!
    ActiveRecord::Base.transaction do
      wipe!
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
  end

  def import_skills
    (@data[:skills] || []).each do |attrs|
      next if attrs[:project_name].present?

      skill = Skill.create!(
        name: attrs[:name],
        description: attrs[:description],
        body: attrs[:body],
        project: nil
      )
      @skill_map[skill_key(nil, attrs[:name])] = skill
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

      skill = Skill.create!(
        name: attrs[:name],
        description: attrs[:description],
        body: attrs[:body],
        project: project
      )
      @skill_map[skill_key(project.name, attrs[:name])] = skill
      @stats[:skills] += 1
    end
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
    workflow.steps.create!(
      name: attrs[:name],
      position: attrs[:position],
      step_type: attrs[:step_type],
      body: attrs[:body],
      config: attrs[:config] || {},
      skill: skill,
      max_retries: attrs[:max_retries] || 0,
      timeout: attrs[:timeout] || 600,
      input_context: attrs[:input_context],
      injectable_only: attrs[:injectable_only] || false
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
        input_context: attrs[:input_context],
        injectable_only: attrs[:injectable_only] || false
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
