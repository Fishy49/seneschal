class DashboardController < ApplicationController
  def index
    @active_runs = Run.active.includes(workflow: :project, run_steps: :step).recent.limit(10)
    @recent_runs = Run.where.not(status: %w[pending running])
                      .includes(workflow: :project)
                      .recent.limit(10)
    @projects = Project.all.order(:name)
    @actionable_tasks = PipelineTask.actionable.includes(:project, :workflow).recent.limit(10)
  end
end
