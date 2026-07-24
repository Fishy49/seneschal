class QuickLaunchController < ApplicationController
  # Backs the Cmd/Ctrl+K launch bar: one JSON payload describing what can be
  # launched, and one action that writes a task and starts its run in a single
  # request.

  def options
    payload = Project.includes(:workflows).order(:name).map do |project|
      {
        id: project.id,
        name: project.name,
        repo_status: project.repo_status,
        workflows: project.workflows.order(:name).map { |w| { id: w.id, name: w.name } }
      }
    end

    render json: { projects: payload }
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

  # The first line becomes the title; the whole description stays as the body,
  # so a one-line launch still satisfies the body presence validation.
  def quick_title(description)
    description.lines.first.to_s.strip.truncate(80)
  end
end
