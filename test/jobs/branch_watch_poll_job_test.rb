require "test_helper"

class BranchWatchPollJobTest < ActiveJob::TestCase
  setup do
    @task = pipeline_tasks(:ready_task)
    @task.update!(
      trigger_type: "github_watch",
      trigger_config: { "repo_url" => "git@github.com:acme/repo.git", "branch" => "main" }
    )
  end

  test "records sha without firing on first sighting" do
    with_stubbed_head_sha("sha-one") do
      assert_no_enqueued_jobs only: ExecuteRunJob do
        BranchWatchPollJob.perform_now
      end
    end
    assert_equal "sha-one", @task.reload.last_seen_sha
  end

  test "fires when sha changes" do
    @task.record_seen_sha!("sha-one")

    with_stubbed_head_sha("sha-two") do
      assert_enqueued_with(job: ExecuteRunJob) do
        BranchWatchPollJob.perform_now
      end
    end
    assert_equal "sha-two", @task.reload.last_seen_sha
  end

  test "does not fire when sha is unchanged" do
    @task.record_seen_sha!("sha-one")

    with_stubbed_head_sha("sha-one") do
      assert_no_enqueued_jobs only: ExecuteRunJob do
        BranchWatchPollJob.perform_now
      end
    end
  end

  test "skips tasks that are not executable" do
    @task.update!(status: "draft", workflow: nil)
    @task.record_seen_sha!("sha-one")

    with_stubbed_head_sha("sha-two") do
      assert_no_enqueued_jobs only: ExecuteRunJob do
        BranchWatchPollJob.perform_now
      end
    end
    # Still advance the recorded SHA so we don't fire again next poll.
    assert_equal "sha-two", @task.reload.last_seen_sha
  end

  private

  def with_stubbed_head_sha(sha)
    original = GitRemote.method(:head_sha)
    GitRemote.define_singleton_method(:head_sha) { |*_| sha }
    yield
  ensure
    GitRemote.define_singleton_method(:head_sha, original)
  end
end
