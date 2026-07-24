# Public, unauthenticated read-only view of a run summary.
#
# This controller renders a PURPOSE-BUILT view. It must never reuse the
# runs/ partials, which render stream logs, tool calls, file contents, error
# output, worktree paths and context variables. See the view for the exact,
# deliberately short list of what is allowed to leave the building.
class SharedRunsController < ApplicationController
  skip_before_action :require_initial_setup
  skip_before_action :require_authentication
  skip_before_action :require_setup

  layout "auth"

  def show
    @share_link = ShareLink.find_by(token: params.expect(:token))
    return render :not_found, status: :not_found unless @share_link
    return render :expired, status: :gone if @share_link.expired?

    @run = @share_link.run
    @run_steps = @run.run_steps.includes(:step).where(parent_run_step_id: nil).order(:position)
  end
end
