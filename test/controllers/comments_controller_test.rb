require "test_helper"

class CommentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
    @run = runs(:completed_run)
  end

  test "POST create adds a comment attributed to the current user" do
    assert_difference "Comment.count", 1 do
      post comments_path, params: {
        commentable_type: "Run", commentable_id: @run.id,
        comment: { body: "Looks good." }
      }, headers: { "HTTP_REFERER" => run_path(@run) }
    end

    assert_redirected_to run_path(@run)
    comment = Comment.last
    assert_equal users(:admin), comment.user
    assert_equal @run, comment.commentable
  end

  test "POST create stores an anchor when given one" do
    post comments_path, params: {
      commentable_type: "RunStep", commentable_id: run_steps(:passed_step).id,
      comment: { body: "This step is slow.", anchor: "replay_step_7" }
    }, headers: { "HTTP_REFERER" => run_path(@run) }

    assert_equal "replay_step_7", Comment.last.anchor
  end

  test "POST create rejects a blank body" do
    assert_no_difference "Comment.count" do
      post comments_path, params: {
        commentable_type: "Run", commentable_id: @run.id,
        comment: { body: "   " }
      }, headers: { "HTTP_REFERER" => run_path(@run) }
    end
    assert_match(/blank/i, flash[:alert])
  end

  test "POST create refuses a commentable type outside the allowlist" do
    assert_no_difference "Comment.count" do
      post comments_path, params: {
        commentable_type: "User", commentable_id: users(:admin).id,
        comment: { body: "sneaky" }
      }
    end
    assert_response :not_found
  end

  test "DELETE destroy removes the author's own comment" do
    comment = @run.comments.create!(user: users(:admin), body: "mine")
    assert_difference "Comment.count", -1 do
      delete comment_path(comment), headers: { "HTTP_REFERER" => run_path(@run) }
    end
  end

  test "DELETE destroy refuses someone else's comment" do
    comment = @run.comments.create!(user: users(:admin), body: "not yours")

    sign_in users(:other)
    assert_no_difference "Comment.count" do
      delete comment_path(comment), headers: { "HTTP_REFERER" => run_path(@run) }
    end
    assert_match(/only delete your own/i, flash[:alert])
  end

  test "an admin may delete someone else's comment" do
    comment = @run.comments.create!(user: users(:other), body: "moderated")

    assert_difference "Comment.count", -1 do
      delete comment_path(comment), headers: { "HTTP_REFERER" => run_path(@run) }
    end
  end

  test "POST create records a comment.created event" do
    assert_difference "Event.count", 1 do
      post comments_path, params: {
        commentable_type: "Run", commentable_id: @run.id,
        comment: { body: "Noted." }
      }, headers: { "HTTP_REFERER" => run_path(@run) }
    end
    assert_equal "comment.created", Event.recent.first.action
  end

  test "the run page renders the discussion thread" do
    @run.comments.create!(user: users(:admin), body: "a prior remark")
    get run_path(@run)
    assert_response :success
    assert_select "##{"comments_run_#{@run.id}"}"
    assert_match "a prior remark", response.body
  end

  test "the task page renders the discussion thread" do
    task = pipeline_tasks(:ready_task)
    task.comments.create!(user: users(:admin), body: "task chatter")
    get pipeline_task_path(task)
    assert_response :success
    assert_match "task chatter", response.body
  end

  test "mentions are tinted rather than rendered as raw html" do
    @run.comments.create!(user: users(:admin), body: "<b>hi</b> @dana")
    get run_path(@run)
    assert_response :success
    assert_no_match(%r{<b>hi</b>}, response.body)
    assert_match(/class="text-accent font-medium">@dana</, response.body)
  end

  test "requires authentication" do
    delete logout_path
    post comments_path, params: {
      commentable_type: "Run", commentable_id: @run.id, comment: { body: "x" }
    }
    assert_redirected_to login_path
  end
end
