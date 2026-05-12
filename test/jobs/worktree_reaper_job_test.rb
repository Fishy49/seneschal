require "test_helper"

class WorktreeReaperJobTest < ActiveJob::TestCase
  test "perform calls WorktreeManager.reap_stale with the configured retention" do
    Setting["worktree_retention_days"] = "3"
    captured = with_stubbed_reap_stale { WorktreeReaperJob.new.perform }
    assert_equal 3.days, captured
  ensure
    Setting.find_by(key: "worktree_retention_days")&.destroy
  end

  test "perform falls back to the default retention when Setting is unset" do
    Setting.find_by(key: "worktree_retention_days")&.destroy
    captured = with_stubbed_reap_stale { WorktreeReaperJob.new.perform }
    assert_equal WorktreeManager::DEFAULT_RETENTION_DAYS.days, captured
  end

  private

  # Minitest 6 dropped Object#stub and Mocha isn't in the Gemfile, so we
  # rebind WorktreeManager.reap_stale around the block (mirrors the
  # alias_method pattern used in execute_run_job_test.rb).
  def with_stubbed_reap_stale
    captured = nil
    mc = WorktreeManager.singleton_class
    mc.send(:alias_method, :__original_reap_stale, :reap_stale)
    mc.send(:define_method, :reap_stale) { |older_than:| captured = older_than }
    begin
      yield
    ensure
      mc.send(:remove_method, :reap_stale)
      mc.send(:alias_method, :reap_stale, :__original_reap_stale)
      mc.send(:remove_method, :__original_reap_stale)
    end
    captured
  end
end
