require "test_helper"

class SyncSkillRepoJobTest < ActiveJob::TestCase
  test "perform invokes SkillRepoSyncer for the repo (verified by sync-error capture)" do
    Setting["skill_repo_root"] = "/tmp/sync_job_root_#{rand(1_000_000)}"
    repo = SkillRepo.create!(name: "job-test-#{rand(1_000_000)}", repo_url: "/nonexistent/path.git")
    SyncSkillRepoJob.new.perform(repo.id)
    repo.reload
    assert repo.last_sync_error.present?, "expected last_sync_error to be set after running the job"
  ensure
    Setting.find_by(key: "skill_repo_root")&.destroy
  end

  test "perform is a no-op when the repo id no longer exists" do
    assert_nothing_raised { SyncSkillRepoJob.new.perform(999_999) }
  end
end

class SyncAllSkillReposJobTest < ActiveJob::TestCase
  test "enqueues SyncSkillRepoJob for every enabled SkillRepo" do
    Setting["skill_repo_root"] = "/tmp/sync_all_root_#{rand(1_000_000)}"
    SkillRepo.delete_all
    enabled = SkillRepo.create!(name: "on-#{rand(1_000_000)}", repo_url: "https://example.com/on.git")
    disabled = SkillRepo.create!(name: "off-#{rand(1_000_000)}",
                                 repo_url: "https://example.com/off.git", enabled: false)

    assert_enqueued_jobs 1, only: SyncSkillRepoJob do
      SyncAllSkillReposJob.new.perform
    end

    job = enqueued_jobs.find { |j| j[:job] == SyncSkillRepoJob }
    assert_equal [enabled.id], job[:args]
    assert_not_includes job[:args], disabled.id
  ensure
    Setting.find_by(key: "skill_repo_root")&.destroy
  end
end
