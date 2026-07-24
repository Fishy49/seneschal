require "test_helper"

class ActivityControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
  end

  test "GET index renders the feed" do
    Event.record("run.started", subject: runs(:completed_run), user: users(:admin))
    get activity_path
    assert_response :success
    assert_select "h1", /Activity/
    assert_match "started run", response.body
    assert_match users(:admin).email, response.body
  end

  test "GET index handles an empty feed" do
    get activity_path
    assert_response :success
    assert_match(/Nothing has happened yet/, response.body)
  end

  test "GET index paginates" do
    (ActivityController::PER_PAGE + 1).times do
      Event.record("run.started", subject: runs(:completed_run), user: users(:admin))
    end

    get activity_path
    assert_response :success
    assert_select "a[href=?]", activity_path(page: 2)

    get activity_path(page: 2)
    assert_response :success
    assert_select "a[href=?]", activity_path(page: 1)
  end

  test "GET index tolerates an event whose subject was deleted" do
    run = runs(:todo_run)
    Event.record("run.completed", subject: run, user: users(:admin))
    run.destroy!

    get activity_path
    assert_response :success
    assert_match(/\(deleted\)/, response.body)
  end

  test "the dashboard shows a recent activity card" do
    Event.record("task.created", subject: pipeline_tasks(:ready_task), user: users(:admin))
    get root_path
    assert_response :success
    assert_select "#dashboard_activity" do
      assert_select "a[href=?]", pipeline_task_path(pipeline_tasks(:ready_task))
    end
  end

  test "requires authentication" do
    delete logout_path
    get activity_path
    assert_redirected_to login_path
  end
end
