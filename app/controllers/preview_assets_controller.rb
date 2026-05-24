class PreviewAssetsController < ApplicationController
  def show
    asset = PreviewAsset.find(params.expect(:id))

    unless asset.file_exists?
      render plain: "Asset file is no longer available (worktree may have been cleaned up).",
             status: :gone
      return
    end

    send_file asset.absolute_path.to_s,
              type: asset.content_type.presence || "application/octet-stream",
              filename: asset.original_filename,
              disposition: "inline"
  end
end
