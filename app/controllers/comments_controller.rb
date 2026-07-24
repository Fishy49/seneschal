class CommentsController < ApplicationController
  before_action :set_comment, only: [:destroy]

  def create
    @comment = commentable.comments.build(
      user: current_user,
      body: params.dig(:comment, :body).to_s.strip,
      anchor: params.dig(:comment, :anchor).presence
    )

    if @comment.save
      redirect_back_or_to(root_path)
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
    redirect_back_or_to(root_path, notice: "Comment deleted.")
  end

  private

  def set_comment
    @comment = Comment.find(params.expect(:id))
  end

  # Allowlisted so the polymorphic type cannot be used to reach an arbitrary
  # model through a crafted request.
  def commentable
    type = params.expect(:commentable_type).to_s
    raise ActiveRecord::RecordNotFound unless Comment::COMMENTABLE_TYPES.include?(type)

    type.constantize.find(params.expect(:commentable_id))
  end
end
