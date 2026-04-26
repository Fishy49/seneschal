class WorkflowCopier
  Result = Data.define(:workflow, :missing_skills, :copied_steps)

  def initialize(source_workflow, target_project)
    @source = source_workflow
    @target = target_project
  end

  def call
    missing_skills = []
    copied_steps = []

    workflow = ActiveRecord::Base.transaction do
      wf = @target.workflows.create!(
        name: unique_name(@source.name),
        description: @source.description,
        trigger_type: @source.trigger_type,
        trigger_config: @source.trigger_config
      )

      @source.steps.order(:position).each do |step|
        resolved_skill = resolve_skill(step.skill, missing_skills)
        new_step = wf.steps.create!(
          name: step.name,
          position: step.position,
          step_type: step.step_type,
          body: step.body,
          config: (step.config || {}).except("context_projects"),
          skill: resolved_skill,
          max_retries: step.max_retries,
          timeout: step.timeout,
          input_context: step.input_context,
          injectable_only: step.injectable_only
        )
        copied_steps << new_step
      end

      wf
    end

    Result.new(workflow: workflow, missing_skills: missing_skills, copied_steps: copied_steps)
  end

  private

  def unique_name(base_name)
    return base_name unless @target.workflows.exists?(name: base_name)

    n = 2
    loop do
      candidate = "#{base_name} (copy #{n})"
      return candidate unless @target.workflows.exists?(name: candidate)
      n += 1
    end
  end

  def resolve_skill(skill, missing_skills)
    return nil if skill.nil?
    return skill if skill.shared?

    target_skill = @target.skills.find_by(name: skill.name)
    return target_skill if target_skill

    missing_skills << "#{skill.project.name}/#{skill.name}"
    skill
  end
end
