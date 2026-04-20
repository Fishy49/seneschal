require "test_helper"

class AssistantPageContextTest < ActiveSupport::TestCase
  test "returns fallback for unknown path" do
    result = AssistantPageContext.summarize("/nonexistent/xyz/123")
    assert_equal "/nonexistent/xyz/123", result[:path]
  end

  test "returns project summary for project show path" do
    project = projects(:seneschal)
    result = AssistantPageContext.summarize("/projects/#{project.id}")
    assert_equal "projects", result[:controller]
    assert_equal "show", result[:action]
    assert_equal project.id, result.dig(:record, :id)
    assert_equal project.name, result.dig(:record, :name)
  end

  test "project summary includes workflow count" do
    project = projects(:seneschal)
    result = AssistantPageContext.summarize("/projects/#{project.id}")
    assert result[:record].key?(:workflows_count)
  end

  test "returns workflow summary for workflow path" do
    project = projects(:seneschal)
    workflow = workflows(:deploy)
    result = AssistantPageContext.summarize("/projects/#{project.id}/workflows/#{workflow.id}")
    assert_equal "workflows", result[:controller]
    assert_equal workflow.id, result.dig(:record, :id)
    assert_equal workflow.name, result.dig(:record, :name)
  end

  test "returns pipeline task summary for task path" do
    task = pipeline_tasks(:ready_task)
    result = AssistantPageContext.summarize("/tasks/#{task.id}")
    assert_equal "pipeline_tasks", result[:controller]
    assert_equal task.id, result.dig(:record, :id)
    assert_equal task.title, result.dig(:record, :title)
  end

  test "pipeline task body is truncated" do
    task = pipeline_tasks(:ready_task)
    task.update!(body: "x" * 1000)
    result = AssistantPageContext.summarize("/tasks/#{task.id}")
    assert result.dig(:record, :body).length <= AssistantPageContext::MAX_BODY_CHARS + 3
  end

  test "returns skill summary for skill path" do
    skill = skills(:shared_skill)
    result = AssistantPageContext.summarize("/skills/#{skill.id}")
    assert_equal "skills", result[:controller]
    assert_equal skill.name, result.dig(:record, :name)
  end

  test "returns root context for dashboard" do
    result = AssistantPageContext.summarize("/")
    assert_equal "/", result[:path]
  end
end
