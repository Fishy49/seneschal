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
    repo = SkillRepo.new(name: "x", repo_url: "https://example.com/x.git", local_path: "/nope")
    assert_not repo.cloned?
  end

  test "branch validation accepts ordinary git branch names" do
    repo = SkillRepo.new(name: "v", repo_url: "https://example.com/x.git", branch: "feature/cool-thing_2")
    assert repo.valid?, repo.errors.full_messages.inspect
  end

  test "branch validation rejects leading dashes (argv-injection guard)" do
    repo = SkillRepo.new(name: "v", repo_url: "https://example.com/x.git", branch: "--upload-pack=evil")
    assert_not repo.valid?
    assert repo.errors[:branch].any?
  end

  test "branch validation rejects shell metacharacters" do
    ["foo bar", "foo;rm", "foo$evil", "foo`evil`", "foo&evil"].each do |bad|
      repo = SkillRepo.new(name: "v", repo_url: "https://example.com/x.git", branch: bad)
      assert_not repo.valid?, "expected #{bad.inspect} to be rejected"
    end
  end

  test "branch validation rejects path-traversal segments" do
    repo = SkillRepo.new(name: "v", repo_url: "https://example.com/x.git", branch: "feature/../../etc")
    assert_not repo.valid?
    assert repo.errors[:branch].any?
  end

  test "branch validation rejects overlong input" do
    repo = SkillRepo.new(name: "v", repo_url: "https://example.com/x.git", branch: "a" * 201)
    assert_not repo.valid?
  end

  test "safe_local_path? accepts paths inside skill_repo_root" do
    Setting["skill_repo_root"] = "/tmp/sk_root"
    repo = SkillRepo.new(name: "x", repo_url: "https://example.com/x.git", local_path: "/tmp/sk_root/x")
    assert repo.safe_local_path?
  ensure
    Setting.find_by(key: "skill_repo_root")&.destroy
  end

  test "safe_local_path? rejects paths outside skill_repo_root" do
    Setting["skill_repo_root"] = "/tmp/sk_root"
    ["/", "/etc", "/tmp/sk_root", "/tmp/sk_root/../etc", "/tmp/other"].each do |bad|
      repo = SkillRepo.new(name: "x", repo_url: "https://example.com/x.git", local_path: bad)
      assert_not repo.safe_local_path?, "expected #{bad.inspect} to be refused"
    end
  ensure
    Setting.find_by(key: "skill_repo_root")&.destroy
  end

  test "destroy_local_clone! is a no-op when the path is outside the root" do
    Setting["skill_repo_root"] = "/tmp/sk_root"
    repo = SkillRepo.new(name: "x", repo_url: "https://example.com/x.git", local_path: "/tmp/other_dangerous")
    assert_not repo.destroy_local_clone!
  ensure
    Setting.find_by(key: "skill_repo_root")&.destroy
  end

  test "repo_url accepts the standard git URL schemes" do
    [
      "https://github.com/org/repo.git",
      "http://example.com/repo.git",
      "ssh://git@host.example/path/repo.git",
      "git://host.example/repo.git",
      "file:///srv/repos/repo.git"
    ].each do |url|
      repo = SkillRepo.new(name: "url-#{rand(1_000_000)}", repo_url: url)
      assert repo.valid?, "expected #{url.inspect} to validate: #{repo.errors.full_messages.inspect}"
    end
  end

  test "repo_url accepts scp-like git remote syntax" do
    [
      "git@github.com:org/repo.git",
      "deploy@host.example:path/to/repo"
    ].each do |url|
      repo = SkillRepo.new(name: "scp-#{rand(1_000_000)}", repo_url: url)
      assert repo.valid?, "expected #{url.inspect} to validate: #{repo.errors.full_messages.inspect}"
    end
  end

  test "repo_url accepts absolute local paths" do
    repo = SkillRepo.new(name: "abs-#{rand(1_000_000)}", repo_url: "/var/git/repo.git")
    assert repo.valid?, repo.errors.full_messages.inspect
  end

  test "repo_url rejects git's ext:: helper scheme (CVE-prone)" do
    repo = SkillRepo.new(name: "bad-#{rand(1_000_000)}", repo_url: "ext::sh -c whoami")
    assert_not repo.valid?
    assert repo.errors[:repo_url].any?
  end

  test "repo_url rejects bare strings without a recognized form" do
    ["u", "x", "not a url", "../relative"].each do |bad|
      repo = SkillRepo.new(name: "bad-#{rand(1_000_000)}", repo_url: bad)
      assert_not repo.valid?, "expected #{bad.inspect} to be rejected"
      assert repo.errors[:repo_url].any?
    end
  end

  test "repo_url rejects scp-like URLs with leading dashes (argv-injection guard)" do
    repo = SkillRepo.new(name: "bad-#{rand(1_000_000)}", repo_url: "-evil:path")
    assert_not repo.valid?
  end
end
