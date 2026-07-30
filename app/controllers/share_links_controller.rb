class ShareLinksController < ApplicationController
  def create
    run = Run.find(params.expect(:run_id))
    link = run.share_links.create!(created_by: current_user)

    redirect_to run_path(run), notice: "Share link created: #{shared_run_url(link.token)}"
  end

  def destroy
    link = ShareLink.find(params.expect(:id))
    run = link.run
    link.destroy

    redirect_to run_path(run), notice: "Share link revoked."
  end
end
