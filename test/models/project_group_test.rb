require "test_helper"

class ProjectGroupTest < ActiveSupport::TestCase
  test "ProjectGroup requires unique name" do
    ProjectGroup.create!(name: "Unique")
    g = ProjectGroup.new(name: "Unique")
    assert_not g.valid?
    assert_includes g.errors[:name], "has already been taken"
  end

  test "ProjectGroup requires name presence" do
    g = ProjectGroup.new(name: "")
    assert_not g.valid?
    assert_includes g.errors[:name], "can't be blank"
  end

  test "renaming group keeps project associations" do
    frontend = project_groups(:frontend)
    projects(:seneschal).update!(project_group: frontend)
    frontend.update!(name: "UI")
    assert_equal "UI", projects(:seneschal).reload.project_group.name
  end

  test "destroying group nullifies project_group_id" do
    projects(:seneschal).update!(project_group: project_groups(:frontend))
    project_groups(:frontend).destroy
    assert_nil Project.find(projects(:seneschal).id).project_group_id
  end

  test "ordered scope returns groups alphabetically" do
    groups = ProjectGroup.ordered
    assert_equal groups.map(&:name), groups.map(&:name).sort
  end
end
