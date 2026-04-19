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

  def remote_branches
    url = params[:repo_url].to_s.strip
    if url.blank?
      render json: { error: "Provide a repo URL." }, status: :unprocessable_content
      return
    end

    branches = GitRemote.branches(url)
    render json: { branches: branches }
  rescue GitRemote::Error => e
    render json: { error: e.message }, status: :unprocessable_content
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

    run = @task.enqueue_run!(reason: "manual")
    redirect_to run_path(run), notice: "Run started for '#{@task.title}'."
  end

  private

  def set_task
    @task = PipelineTask.find(params[:id])
  end

  def task_params
    permitted = params.expect(
      pipeline_task: [
        :title, :body, :kind, :status, :project_id, :workflow_id,
        :context_files, :trigger_type,
        { trigger_config: [:cron_preset, :cron, :repo_url, :branch] }
      ]
    )

    if permitted[:context_files].is_a?(String)
      permitted[:context_files] = begin
        JSON.parse(permitted[:context_files])
      rescue StandardError
        []
      end
    end

    permitted[:trigger_config] = build_trigger_config(permitted[:trigger_type], permitted[:trigger_config])
    permitted
  end

  def build_trigger_config(type, raw)
    raw = (raw || {}).to_h.with_indifferent_access
    existing = @task&.trigger_config || {}

    case type
    when "cron"
      cron = raw[:cron_preset].presence == "custom" ? raw[:cron].to_s.strip : raw[:cron_preset].to_s.strip
      { "cron" => cron, "last_fired_at" => existing["last_fired_at"] }.compact
    when "github_watch"
      new_url = raw[:repo_url].to_s.strip
      new_branch = raw[:branch].to_s.strip
      # Reset last_seen_sha when the user changes repo or branch so the next
      # poll arms the watcher instead of firing on stale state.
      keep_sha = existing["repo_url"] == new_url && existing["branch"] == new_branch
      {
        "repo_url" => new_url,
        "branch" => new_branch,
        "last_seen_sha" => keep_sha ? existing["last_seen_sha"] : nil
      }.compact
    else
      {}
    end
  end
end
