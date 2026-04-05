require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "valid project" do
    project = Project.new(
      name: "NewProject",
      repo_url: "https://github.com/test/new.git",
      local_path: Rails.root.join("tmp/test_repos/new_project").to_s
    )
    assert project.valid?
  end

  test "requires name" do
    project = Project.new(repo_url: "https://github.com/test/x.git", local_path: "/tmp/x")
    assert_not project.valid?
    assert_includes project.errors[:name], "can't be blank"
  end

  test "requires unique name" do
    project = Project.new(
      name: projects(:seneschal).name,
      repo_url: "https://github.com/test/dup.git",
      local_path: "/tmp/dup"
    )
    assert_not project.valid?
    assert_includes project.errors[:name], "has already been taken"
  end

  test "requires repo_url" do
    project = Project.new(name: "NoURL", local_path: "/tmp/nourl")
    assert_not project.valid?
    assert_includes project.errors[:repo_url], "can't be blank"
  end

  test "requires local_path" do
    project = Project.new(name: "NoPath", repo_url: "https://github.com/test/x.git")
    assert_not project.valid?
    assert_includes project.errors[:local_path], "can't be blank"
  end

  test "validates repo_status inclusion" do
    project = projects(:seneschal)
    project.repo_status = "invalid"
    assert_not project.valid?
  end

  test "repo_ready? returns true for ready status" do
    assert projects(:seneschal).repo_ready?
  end

  test "repo_ready? returns false for other statuses" do
    assert_not projects(:other_project).repo_ready?
  end

  test "repo_nwo extracts owner/repo from HTTPS URL" do
    project = projects(:seneschal)
    assert_equal "test/seneschal", project.repo_nwo
  end

  test "repo_nwo extracts owner/repo from SSH URL" do
    project = Project.new(repo_url: "git@github.com:owner/repo.git")
    assert_equal "owner/repo", project.repo_nwo
  end

  test "repo_owner and repo_name split correctly" do
    project = projects(:seneschal)
    assert_equal "test", project.repo_owner
    assert_equal "seneschal", project.repo_name
  end

  test "has_many workflows" do
    project = projects(:seneschal)
    assert_includes project.workflows, workflows(:deploy)
  end

  test "has_many skills" do
    project = projects(:seneschal)
    assert_includes project.skills, skills(:project_skill)
  end

  test "has_many pipeline_tasks" do
    project = projects(:seneschal)
    assert_includes project.pipeline_tasks, pipeline_tasks(:ready_task)
  end

  test "destroying project destroys workflows" do
    project = Project.create!(
      name: "Disposable", repo_url: "https://github.com/t/d.git",
      local_path: Rails.root.join("tmp/test_repos/disposable").to_s
    )
    project.workflows.create!(name: "w1", trigger_type: "manual")
    project.workflows.create!(name: "w2", trigger_type: "manual")
    assert_difference "Workflow.count", -2 do
      project.destroy
    end
  end

  test "detect_repo_status sets ready when .git exists" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".git"))
      project = Project.new(
        name: "DetectTest",
        repo_url: "https://github.com/test/detect.git",
        local_path: dir
      )
      project.save!
      assert_equal "ready", project.repo_status
    end
  end
end
