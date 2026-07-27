class DashboardController < ApplicationController
  ACTIVE_LIMIT = 10
  RECENT_LIMIT = 8
  FINISHED = ["completed", "failed", "stopped"].freeze

  def index
    @awaiting_runs = Run.awaiting_approval.includes(:started_by, :pipeline_task, workflow: :project).recent
    @awaiting_viewers = @awaiting_runs.to_h { |run| [run.id, RunPresence.new(run.id).viewers] }
    # Parked runs get their own banner above, so keep them out of the active
    # list rather than listing the same run twice.
    @active_runs = Run.active.where.not(status: "awaiting_approval")
                      .includes(:started_by, :pipeline_task, workflow: :project, run_steps: :step)
                      .recent.limit(ACTIVE_LIMIT)
    @recent_runs = Run.where(status: FINISHED)
                      .includes(:started_by, :pipeline_task, :run_steps, workflow: :project)
                      .recent.limit(RECENT_LIMIT)
    @projects = Project.order(:name)
    @recent_events = Event.includes(:user, :subject).recent.limit(5)
  end
end
