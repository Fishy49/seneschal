require "test_helper"

class SharedRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @run = runs(:completed_run)
    @link = @run.share_links.create!(created_by: users(:admin))
  end

  test "a valid token renders the summary without signing in" do
    get shared_run_path(@link.token)
    assert_response :success

    assert_match @run.pipeline_task.title, response.body
    assert_match "Seneschal", response.body
    assert_match "Deploy Pipeline", response.body
    assert_select "h1", /#{Regexp.escape(@run.pipeline_task.title)}/
  end

  test "step names, statuses and durations are shown" do
    get shared_run_path(@link.token)
    assert_response :success
    assert_match run_steps(:passed_step).step.name, response.body
    assert_match(/passed/, response.body)
  end

  test "nothing sensitive leaves the building" do
    run_step = run_steps(:passed_step)
    get shared_run_path(@link.token)
    assert_response :success

    body = response.body
    # stream_log markers
    assert_no_match(/claude-sonnet-4-20250514/, body, "model from stream_log leaked")
    assert_no_match(/total_cost_usd/, body, "raw stream_log leaked")
    # step output and error output
    assert_no_match(/#{Regexp.escape(run_step.output)}/, body, "step output leaked")
    assert_no_match(%r{feature/auth}, body, "branch name from output leaked")
    # paths and context
    assert_no_match(%r{tmp/test_repos}, body, "repo path leaked")
    assert_no_match(/worktree/i, body, "worktree detail leaked")
    assert_no_match(/REPO_PATH/, body, "environment leaked")
  end

  test "the error message of a failed run is not exposed" do
    failed = runs(:failed_run)
    link = failed.share_links.create!
    get shared_run_path(link.token)
    assert_response :success
    assert_no_match(/exit code 1/, response.body, "error_message leaked")
  end

  test "comments on the run are not exposed" do
    @run.comments.create!(user: users(:admin), body: "internal chatter about the client")
    get shared_run_path(@link.token)
    assert_response :success
    assert_no_match(/internal chatter/, response.body)
  end

  test "an unknown token renders a not-found page rather than a 500" do
    get shared_run_path("nope-not-a-real-token")
    assert_response :not_found
    assert_match(/Nothing here/, response.body)
  end

  test "a revoked link stops working immediately" do
    token = @link.token
    @link.destroy
    get shared_run_path(token)
    assert_response :not_found
  end

  test "an expired link renders a friendly page, not a crash" do
    @link.update!(expires_at: 1.day.ago)
    get shared_run_path(@link.token)
    assert_response :gone
    assert_match(/expired/i, response.body)
  end

  test "the shared page does not require the app to be set up" do
    Setting.where(key: ["claude_cli", "gh_cli"]).destroy_all
    get shared_run_path(@link.token)
    assert_response :success
  end
end
