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

  test "the run page renders the unified discussion feed" do
    @run.comments.create!(user: users(:admin), body: "a prior remark")
    get run_path(@run)
    assert_response :success
    assert_select "#run_discussion"
    assert_match "a prior remark", response.body
  end

  test "the unified feed aggregates run and step comments chronologically" do
    step_comment = run_steps(:passed_step).comments.create!(user: users(:admin), body: "step remark")
    run_comment = @run.comments.create!(user: users(:admin), body: "run remark")

    get run_path(@run)
    assert_select "#run_discussion #comment_#{step_comment.id}"
    assert_select "#run_discussion #comment_#{run_comment.id}"
    assert response.body.index("step remark") < response.body.index("run remark")
  end

  test "a step comment in the feed wears a chip linking back to its step" do
    step = run_steps(:passed_step)
    step.comments.create!(user: users(:admin), body: "slow step")

    get run_path(@run)
    assert_select "#run_discussion a[href=?]", "#run_step_#{step.id}", text: /#{step.step.name}/
  end

  test "the composer offers the run and each step as a target" do
    get run_path(@run)
    assert_select "#discussion select[name=commentable]" do
      assert_select "option[value=?]", "Run:#{@run.id}"
      assert_select "option[value=?]", "RunStep:#{run_steps(:passed_step).id}"
    end
  end

  test "POST create accepts the composer's encoded target" do
    step = run_steps(:passed_step)
    assert_difference "Comment.count", 1 do
      post comments_path, params: {
        commentable: "RunStep:#{step.id}",
        comment: { body: "via the picker" }
      }, headers: { "HTTP_REFERER" => run_path(@run) }
    end
    assert_equal step, Comment.last.commentable
  end

  test "POST create refuses an encoded target outside the allowlist" do
    assert_no_difference "Comment.count" do
      post comments_path, params: {
        commentable: "User:#{users(:admin).id}",
        comment: { body: "sneaky" }
      }
    end
    assert_response :not_found
  end

  test "POST create over turbo stream appends to the unified feed without a reload" do
    post comments_path, params: {
      commentable: "Run:#{@run.id}",
      comment: { body: "streamed in" }
    }, as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream action="append" target="run_discussion"/, response.body)
    assert_match "streamed in", response.body
  end

  test "DELETE destroy over turbo stream removes the comment element" do
    comment = @run.comments.create!(user: users(:admin), body: "mine")
    delete comment_path(comment), as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream action="remove" target="comment_#{comment.id}"/, response.body)
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
