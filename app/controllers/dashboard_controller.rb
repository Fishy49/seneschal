class DashboardController < ApplicationController
  def index
    @awaiting_runs = Run.awaiting_approval.includes(:pipeline_task, workflow: :project).recent
    # Parked runs get their own section above, so keep them out of Active Runs
    # rather than listing the same run twice.
    @active_runs = Run.active.where.not(status: "awaiting_approval")
                      .includes(:pipeline_task, workflow: :project, run_steps: :step)
                      .recent.limit(10)
    @recent_runs = Run.where.not(status: ["pending", "running"])
                      .includes(:pipeline_task, workflow: :project)
                      .recent.limit(10)
    @projects = Project.order(:name)
    @actionable_tasks = PipelineTask.actionable.includes(:project, :workflow).recent.limit(10)
  end
end
