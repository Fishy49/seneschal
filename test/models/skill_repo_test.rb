require "test_helper"

class SkillRepoTest < ActiveSupport::TestCase
  test "branch defaults to main on create" do
    repo = SkillRepo.new(name: "x", repo_url: "https://example.com/x.git")
    repo.valid?
    assert_equal "main", repo.branch
  end

  test "local_path is auto-computed from the name under skill_repo_root" do
    Setting["skill_repo_root"] = "/tmp/sk_root"
    repo = SkillRepo.new(name: "Cool Skills!", repo_url: "https://example.com/x.git")
    repo.valid?
    assert_equal "/tmp/sk_root/cool-skills", repo.local_path
  ensure
    Setting.find_by(key: "skill_repo_root")&.destroy
  end

  test "active_by_priority returns enabled repos in priority then created_at order" do
    Setting["skill_repo_root"] = "/tmp/sk_root"
    SkillRepo.delete_all
    a = SkillRepo.create!(name: "a", repo_url: "https://example.com/a.git", priority: 100)
    b = SkillRepo.create!(name: "b", repo_url: "https://example.com/b.git", priority: 50)
    c = SkillRepo.create!(name: "c", repo_url: "https://example.com/c.git", priority: 50, enabled: false)

    ordered = SkillRepo.active_by_priority.to_a
    assert_equal [b, a], ordered
    assert_not_includes ordered, c
  ensure
    Setting.find_by(key: "skill_repo_root")&.destroy
  end

  test "cloned? checks for a .git directory at local_path" do
    repo = SkillRepo.new(name: "x", repo_url: "x", local_path: "/nope")
    assert_not repo.cloned?
  end
end
