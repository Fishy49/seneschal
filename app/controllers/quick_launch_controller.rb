class QuickLaunchController < ApplicationController
  # Backs the Cmd/Ctrl+K launch bar: one JSON payload describing what can be
  # launched, and one action that writes a task and starts its run in a single
  # request.

  PAGES = [
    ["Inbox", :root_path], ["Board", :pipeline_tasks_path], ["Runs", :runs_path],
    ["Library", :skills_path], ["Activity", :activity_path], ["Account", :account_path]
  ].freeze

  def options
    payload = Project.includes(workflows: [:steps, :runs]).order(:name).map do |project|
      {
        id: project.id,
        name: project.name,
        repo_status: project.repo_status,
        workflows: project.workflows.sort_by(&:name).map { |w| workflow_option(w) }
      }
    end

    render json: { projects: payload }
  end

  # Jump-to search behind the palette: pages, projects, workflows, tasks,
  # skills, and "#42"-style run ids, capped small because it renders as a
  # keyboard-navigable list, not a results page.
  def search
    q = params[:q].to_s.strip
    return render json: { results: [] } if q.length < 2

    like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
    results = page_results(q) + record_results(like) + run_result(q) + skill_results(like)
    render json: { results: results.first(10) }
  end

  def create
    description = params[:description].to_s.strip
    task = PipelineTask.new(
      title: quick_title(description),
      body: description,
      kind: "feature",
      status: "ready",
      project_id: params[:project_id].presence,
      workflow_id: params[:workflow_id].presence,
      created_by: current_user
    )

    unless task.save
      render json: { error: task.errors.full_messages.to_sentence }, status: :unprocessable_content
      return
    end

    Event.record("task.created", subject: task, user: current_user)
    run = task.enqueue_run!(reason: "manual", started_by: current_user)
    Event.record("run.started", subject: run, user: current_user)

    render json: { redirect: run_path(run) }
  end

  private

  def page_results(query)
    PAGES.filter_map do |label, helper|
      next unless label.downcase.include?(query.downcase)

      { type: "page", label: label, sublabel: "Go to", url: send(helper) }
    end
  end

  def record_results(like)
    results = Project.where("name LIKE ?", like).order(:name).limit(4).map do |project|
      { type: "project", label: project.name, sublabel: "Project", url: project_path(project) }
    end
    Workflow.includes(:project).where("name LIKE ?", like).order(:name).limit(4).each do |workflow|
      results << { type: "workflow", label: workflow.name, sublabel: workflow.project.name,
                   url: project_workflow_path(workflow.project, workflow) }
    end
    PipelineTask.active.includes(:project).where("title LIKE ?", like).recent.limit(5).each do |task|
      results << { type: "task", label: task.title, sublabel: "#{task.project.name} · #{task.status}",
                   url: pipeline_task_path(task) }
    end
    results
  end

  def run_result(query)
    match = query.match(/\A#?(\d+)\z/)
    run = match && Run.find_by(id: match[1])
    return [] unless run

    [{ type: "run", label: helpers.run_display_name(run), sublabel: "Run ##{run.id}", url: run_path(run) }]
  end

  def skill_results(like)
    Skill.where("name LIKE ?", like).order(:name).limit(4).map do |skill|
      { type: "skill", label: skill.name, sublabel: "Skill", url: skill_path(skill) }
    end
  end

  # Stats and access are pre-formatted here so the palette can show the same
  # confidence glance as the composer without duplicating the wording in JS.
  def workflow_option(workflow)
    {
      id: workflow.id,
      name: workflow.name,
      stats: helpers.workflow_stats_line(workflow.stats) || "never run",
      access: WorkflowAccessSummary.for(workflow).map(&:label).join(", ")
    }
  end

  # The first line becomes the title; the whole description stays as the body,
  # so a one-line launch still satisfies the body presence validation.
  def quick_title(description)
    description.lines.first.to_s.strip.truncate(80)
  end
end
