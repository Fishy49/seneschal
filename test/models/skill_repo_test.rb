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

  test "branch validation accepts ordinary git branch names" do
    repo = SkillRepo.new(name: "v", repo_url: "u", branch: "feature/cool-thing_2")
    assert repo.valid?, repo.errors.full_messages.inspect
  end

  test "branch validation rejects leading dashes (argv-injection guard)" do
    repo = SkillRepo.new(name: "v", repo_url: "u", branch: "--upload-pack=evil")
    assert_not repo.valid?
    assert repo.errors[:branch].any?
  end

  test "branch validation rejects shell metacharacters" do
    ["foo bar", "foo;rm", "foo$evil", "foo`evil`", "foo&evil"].each do |bad|
      repo = SkillRepo.new(name: "v", repo_url: "u", branch: bad)
      assert_not repo.valid?, "expected #{bad.inspect} to be rejected"
    end
  end

  test "branch validation rejects path-traversal segments" do
    repo = SkillRepo.new(name: "v", repo_url: "u", branch: "feature/../../etc")
    assert_not repo.valid?
    assert repo.errors[:branch].any?
  end

  test "branch validation rejects overlong input" do
    repo = SkillRepo.new(name: "v", repo_url: "u", branch: "a" * 201)
    assert_not repo.valid?
  end

  test "safe_local_path? accepts paths inside skill_repo_root" do
    Setting["skill_repo_root"] = "/tmp/sk_root"
    repo = SkillRepo.new(name: "x", repo_url: "u", local_path: "/tmp/sk_root/x")
    assert repo.safe_local_path?
  ensure
    Setting.find_by(key: "skill_repo_root")&.destroy
  end

  test "safe_local_path? rejects paths outside skill_repo_root" do
    Setting["skill_repo_root"] = "/tmp/sk_root"
    ["/", "/etc", "/tmp/sk_root", "/tmp/sk_root/../etc", "/tmp/other"].each do |bad|
      repo = SkillRepo.new(name: "x", repo_url: "u", local_path: bad)
      assert_not repo.safe_local_path?, "expected #{bad.inspect} to be refused"
    end
  ensure
    Setting.find_by(key: "skill_repo_root")&.destroy
  end

  test "destroy_local_clone! is a no-op when the path is outside the root" do
    Setting["skill_repo_root"] = "/tmp/sk_root"
    repo = SkillRepo.new(name: "x", repo_url: "u", local_path: "/tmp/other_dangerous")
    assert_not repo.destroy_local_clone!
  ensure
    Setting.find_by(key: "skill_repo_root")&.destroy
  end
end
