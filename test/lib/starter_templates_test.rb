require "test_helper"
require "tmpdir"

# The pack is only useful if it still imports. These run the real importer
# against a real (temporary) project, so a change to the export format that
# strands the starters fails here rather than on somebody's first install.
class StarterTemplatesTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir("seneschal-starters")
    @skills_root = File.join(@dir, "skills")
    FileUtils.mkdir_p(@skills_root)
    Setting["skills_global_roots"] = @skills_root

    @project = Project.create!(name: "Starter Target",
                               repo_url: "git@example.com:acme/starter.git",
                               local_path: File.join(@dir, "repo"))
  end

  teardown do
    Setting.where(key: "skills_global_roots").destroy_all
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
  end

  test "the registry lists every bundled file, in order" do
    keys = Seneschal::StarterTemplates.list.map(&:key)
    on_disk = Dir.glob(Seneschal::StarterTemplates::ROOT.join("*.json")).map { |p| File.basename(p, ".json") }

    assert_equal on_disk.sort, keys.sort
    assert_equal "classic_feature", keys.first
  end

  test "find returns nil for an unknown key" do
    assert_nil Seneschal::StarterTemplates.find("nope")
    assert_equal "bugfix", Seneschal::StarterTemplates.find("bugfix").key
  end

  Seneschal::StarterTemplates.list.each do |template|
    test "#{template.key} imports into a fresh project" do
      result = WorkflowImporter.new(template.payload, target_project: @project).call

      assert_equal @project.id, result.workflow.project_id
      assert_equal template.step_types.size, result.workflow.steps.count
      assert_equal template.step_types, result.workflow.steps.order(:position).map(&:step_type)
    end

    test "#{template.key} materialises its skills with valid frontmatter" do
      result = WorkflowImporter.new(template.payload, target_project: @project).call

      skill_steps = result.workflow.steps.select { |s| s.step_type == "skill" }
      assert skill_steps.any?, "expected #{template.key} to use at least one skill"

      skill_steps.each do |step|
        assert step.skill.present?, "step #{step.name} has no skill"
        assert File.exist?(step.skill.skill_md_path), "SKILL.md missing for #{step.skill.name}"
        assert_equal step.skill.name, step.skill.frontmatter["name"]
        assert step.skill.frontmatter["description"].present?
        assert step.skill.body.present?
      end
    end
  end

  test "the pack references only variables the pipeline actually publishes" do
    Seneschal::StarterTemplates.list.each do |template|
      steps = template.payload.dig("seneschal_workflow_export", "workflow", "steps")
      body = steps.to_json

      # ${branch} was a shipped typo; the PR step publishes branch_name.
      assert_no_match(/\$\{branch\}/, body, "#{template.key} uses ${branch}")
    end
  end

  test "using the same template twice suffixes the second copy" do
    template = Seneschal::StarterTemplates.find("bugfix")
    first = WorkflowImporter.new(template.payload, target_project: @project).call
    second = WorkflowImporter.new(template.payload, target_project: @project).call

    assert_not_equal first.workflow.name, second.workflow.name
    assert_equal 2, @project.workflows.count
  end
end
