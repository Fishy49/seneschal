class DataExporter
  def call
    {
      seneschal_export: {
        version: 1,
        exported_at: Time.current.iso8601,
        skills: export_skills,
        step_templates: export_step_templates,
        projects: export_projects
      }
    }
  end

  private

  def export_skills
    Skill.includes(:project).order(:name).map do |skill|
      {
        name: skill.name,
        description: skill.description,
        body: skill.body,
        project_name: skill.project&.name
      }
    end
  end

  def export_step_templates
    StepTemplate.includes(skill: :project).ordered.map do |t|
      {
        name: t.name,
        step_type: t.step_type,
        body: t.body,
        config: t.config,
        skill_name: t.skill&.name,
        skill_project_name: t.skill&.project&.name,
        max_retries: t.max_retries,
        timeout: t.timeout,
        input_context: t.input_context,
        injectable_only: t.injectable_only
      }
    end
  end

  def export_projects
    Project.includes(workflows: { steps: { skill: :project } }, pipeline_tasks: :workflow)
           .order(:name).map { |project| export_project(project) }
  end

  def export_project(project)
    {
      name: project.name,
      repo_url: project.repo_url,
      local_path: project.local_path,
      description: project.description,
      workflows: project.workflows.sort_by(&:name).map { |w| export_workflow(w) },
      tasks: project.pipeline_tasks.sort_by(&:title).map { |t| export_task(t) }
    }
  end

  def export_workflow(workflow)
    {
      name: workflow.name,
      description: workflow.description,
      trigger_type: workflow.trigger_type,
      trigger_config: workflow.trigger_config,
      steps: workflow.steps.sort_by(&:position).map { |s| export_step(s) }
    }
  end

  def export_step(step)
    {
      name: step.name,
      position: step.position,
      step_type: step.step_type,
      body: step.body,
      config: step.config,
      skill_name: step.skill&.name,
      skill_project_name: step.skill&.project&.name,
      max_retries: step.max_retries,
      timeout: step.timeout,
      input_context: step.input_context,
      injectable_only: step.injectable_only
    }
  end

  def export_task(task)
    {
      title: task.title,
      body: task.body,
      kind: task.kind,
      status: task.status,
      workflow_name: task.workflow&.name
    }
  end
end
