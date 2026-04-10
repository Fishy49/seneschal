require "open3"

class PipelineTasksController < ApplicationController
  before_action :set_task, only: [:show, :edit, :update, :destroy, :execute, :mark_ready, :archive, :unarchive]

  def index
    @show_archived = params[:archived] == "1"
    @tasks = PipelineTask.includes(:project, :workflow).recent
    @tasks = @show_archived ? @tasks.archived : @tasks.active

    @tasks = @tasks.where(project_id: params[:project_id]) if params[:project_id].present?
    @tasks = @tasks.where(status: params[:status]) if params[:status].present?
    @tasks = @tasks.where(kind: params[:kind]) if params[:kind].present?
    @tasks = @tasks.where("title LIKE ?", "%#{params[:q]}%") if params[:q].present?

    @projects = Project.order(:name)
  end

  def show
    @runs = @task.runs.includes(:workflow).recent.limit(10)
  end

  def new
    @task = PipelineTask.new(
      project_id: params[:project_id],
      kind: "feature",
      status: "draft"
    )
  end

  def edit; end

  def create
    @task = PipelineTask.new(task_params)
    if @task.save
      redirect_to @task, notice: "Task created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @task.update(task_params)
      redirect_to @task, notice: "Task updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @task.destroy
    redirect_to pipeline_tasks_path, notice: "Task deleted."
  end

  def format_body
    raw_text = params[:body].to_s.strip
    if raw_text.blank?
      render json: { error: "No text to format." }, status: :unprocessable_content
      return
    end

    prompt = <<~PROMPT
      Format the following rough notes into a concise markdown feature specification. Include:

      1. A brief description of what the feature does and why (2-3 sentences max)
      2. An "## Acceptance criteria" section with concrete, testable bullet points

      Keep it tight — no filler, no implementation details. Just what and why.

      Here are the notes:

      #{raw_text}
    PROMPT

    stdout, stderr, status = Open3.capture3(
      "claude", "-p", "--model", "claude-haiku-4-5-20251001",
      stdin_data: prompt
    )

    if status.success? && stdout.present?
      formatted = stdout.strip.gsub(/\A```\w*\n?/, "").gsub(/\n?```\z/, "").strip
      render json: { formatted: formatted }
    else
      render json: { error: stderr.presence || "Claude CLI failed." }, status: :unprocessable_content
    end
  end

  def archive
    @task.update!(archived_at: Time.current)
    redirect_to pipeline_tasks_path, notice: "Task archived."
  end

  def unarchive
    @task.update!(archived_at: nil)
    redirect_to @task, notice: "Task unarchived."
  end

  def mark_ready
    if @task.workflow.blank?
      redirect_to @task, alert: "Assign a workflow before marking ready."
      return
    end

    @task.update!(status: "ready")
    redirect_to @task, notice: "Task is ready to execute."
  end

  def execute
    unless @task.executable?
      redirect_to @task, alert: "Task is not executable. Assign a workflow and mark it ready."
      return
    end

    @task.update!(status: "running")

    project = @task.project

    run = @task.runs.create!(
      workflow: @task.workflow,
      input: {
        "task_id" => @task.id,
        "task_title" => @task.title,
        "task_kind" => @task.kind
      },
      context: {
        "task_title" => @task.title,
        "task_body" => @task.body,
        "task_kind" => @task.kind,
        "repo_owner" => project.repo_owner,
        "repo_name" => project.repo_name
      }
    )

    ExecuteRunJob.perform_later(run)
    redirect_to run_path(run), notice: "Run started for '#{@task.title}'."
  end

  private

  def set_task
    @task = PipelineTask.find(params[:id])
  end

  def task_params
    params.expect(pipeline_task: [:title, :body, :kind, :status, :project_id, :workflow_id])
  end
end
