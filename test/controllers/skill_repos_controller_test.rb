require "test_helper"

class SkillReposControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
    Setting["skill_repo_root"] = "/tmp/srct_#{rand(1_000_000)}"
  end

  teardown do
    Setting.find_by(key: "skill_repo_root")&.destroy
  end

  test "GET index renders empty state when no repos" do
    SkillRepo.delete_all
    get skill_repos_path
    assert_response :success
    assert_select "h1", /Skill Repos/i
  end

  test "GET index lists registered repos" do
    repo = SkillRepo.create!(name: "test-pack", repo_url: "https://example.com/x.git")
    get skill_repos_path
    assert_response :success
    assert_includes response.body, "test-pack"
    repo.destroy
  end

  test "GET new renders form" do
    get new_skill_repo_path
    assert_response :success
    assert_select "h1", /Add Skill Repo/i
  end

  test "POST create registers a repo and enqueues sync" do
    assert_difference "SkillRepo.count", 1 do
      assert_enqueued_jobs 1, only: SyncSkillRepoJob do
        post skill_repos_path, params: {
          skill_repo: { name: "newone-#{rand(1_000_000)}", repo_url: "https://example.com/x.git" }
        }
      end
    end
    assert_redirected_to skill_repo_path(SkillRepo.last)
  end

  test "POST create rejects missing repo_url" do
    assert_no_difference "SkillRepo.count" do
      post skill_repos_path, params: { skill_repo: { name: "x", repo_url: "" } }
    end
    assert_response :unprocessable_content
  end

  test "GET show renders metadata + skills list" do
    repo = SkillRepo.create!(name: "show-test-#{rand(1_000_000)}", repo_url: "https://example.com/x.git")
    Skill.create!(name: "active-skill", source_kind: "skill_repo", relative_path: "active-skill",
                  skill_repo: repo)
    Skill.create!(name: "old-skill", source_kind: "skill_repo", relative_path: "old-skill",
                  skill_repo: repo, archived_at: 1.day.ago)

    get skill_repo_path(repo)
    assert_response :success
    assert_includes response.body, "active-skill"
    assert_includes response.body, "old-skill"
    assert_includes response.body, "Archived skills"
    repo.destroy
  end

  test "POST sync enqueues a SyncSkillRepoJob" do
    repo = SkillRepo.create!(name: "sync-#{rand(1_000_000)}", repo_url: "https://example.com/x.git")
    assert_enqueued_jobs 1, only: SyncSkillRepoJob do
      post sync_skill_repo_path(repo)
    end
    assert_redirected_to skill_repo_path(repo)
    repo.destroy
  end

  test "DELETE destroy removes the repo and its Skill records" do
    repo = SkillRepo.create!(name: "doomed-#{rand(1_000_000)}", repo_url: "https://example.com/x.git")
    Skill.create!(name: "to-delete", source_kind: "skill_repo", relative_path: "to-delete", skill_repo: repo)

    assert_difference "SkillRepo.count", -1 do
      assert_difference "Skill.count", -1 do
        delete skill_repo_path(repo)
      end
    end
    assert_redirected_to skill_repos_path
  end

  test "non-admin users are redirected away" do
    sign_out
    sign_in users(:other)
    get skill_repos_path
    assert_redirected_to root_path
  end
end
