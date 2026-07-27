class CommentsController < ApplicationController
  before_action :set_comment, only: [:destroy]

  def create
    @comment = commentable.comments.build(
      user: current_user,
      body: params.dig(:comment, :body).to_s.strip,
      anchor: params.dig(:comment, :anchor).presence
    )

    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back_or_to(root_path) }
      end
    else
      redirect_back_or_to(root_path, alert: @comment.errors.full_messages.to_sentence)
    end
  end

  def destroy
    unless @comment.user_id == current_user.id || current_user.admin?
      redirect_back_or_to(root_path, alert: "You can only delete your own comments.")
      return
    end

    @comment.destroy
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@comment) }
      format.html { redirect_back_or_to(root_path, notice: "Comment deleted.") }
    end
  end

  private

  def set_comment
    @comment = Comment.find(params.expect(:id))
  end

  # The run page composer posts one "Type:id" value from its target picker;
  # the task thread still posts split type/id fields. Both funnel through the
  # same allowlist so the polymorphic type cannot be used to reach an
  # arbitrary model through a crafted request.
  def commentable
    type, id = if params[:commentable].present?
                 params.expect(:commentable).to_s.split(":", 2)
               else
                 [params.expect(:commentable_type).to_s, params.expect(:commentable_id)]
               end
    raise ActiveRecord::RecordNotFound unless Comment::COMMENTABLE_TYPES.include?(type)

    type.constantize.find(id)
  end
end
