class AssistantPageContext
  MAX_BODY_CHARS = 500

  def self.summarize(path)
    new(path).summarize
  end

  def initialize(path)
    @path = path
  end

  def summarize
    params = Rails.application.routes.recognize_path(@path)
    build_summary(params)
  rescue ActionController::RoutingError
    { path: @path }
  end

  private

  def build_summary(params)
    controller = params[:controller]
    action = params[:action]
    id = params[:id]

    record_summary = case controller
                     when "projects"       then project_summary(id)
                     when "workflows"      then workflow_summary(id, params[:project_id])
                     when "runs"           then run_summary(id)
                     when "pipeline_tasks" then pipeline_task_summary(id)
                     when "skills"         then skill_summary(id)
                     when "step_templates" then step_template_summary(id)
                     end

    { path: @path, controller: controller, action: action, record: record_summary }.compact
  end

  def project_summary(id)
    return unless id
    project = Project.find_by(id: id)
    return unless project
    {
      id: project.id,
      name: project.name,
      description: project.description,
      repo_status: project.repo_status,
      workflows_count: project.workflows.count,
      skills_count: project.skills.count
    }
  end

  def workflow_summary(id, project_id)
    return unless id
    workflow = Workflow.find_by(id: id)
    return unless workflow
    {
      id: workflow.id,
      name: workflow.name,
      trigger_type: workflow.trigger_type,
      steps_count: workflow.steps.count,
      project_id: workflow.project_id,
      project_name: workflow.project.name
    }
  end

  def run_summary(id)
    return unless id
    run = Run.find_by(id: id)
    return unless run
    {
      id: run.id,
      status: run.status,
      workflow_name: run.workflow.name,
      project_name: run.workflow.project.name,
      steps_count: run.run_steps.count
    }
  end

  def pipeline_task_summary(id)
    return unless id
    task = PipelineTask.find_by(id: id)
    return unless task
    {
      id: task.id,
      title: task.title,
      kind: task.kind,
      status: task.status,
      body: task.body.to_s.truncate(MAX_BODY_CHARS)
    }
  end

  def skill_summary(id)
    return unless id
    skill = Skill.find_by(id: id)
    return unless skill
    {
      id: skill.id,
      name: skill.name,
      description: skill.description,
      shared: skill.shared?
    }
  end

  def step_template_summary(id)
    return unless id
    template = StepTemplate.find_by(id: id)
    return unless template
    {
      id: template.id,
      name: template.name,
      step_type: template.step_type
    }
  end
end
