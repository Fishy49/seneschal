require "test_helper"

class TemplateRendererTest < ActiveSupport::TestCase
  test "replaces variables with context values" do
    body = "Hello ${name}, welcome to ${project}"
    result = TemplateRenderer.new(body, { name: "Rick", project: "Seneschal" }).render
    assert_equal "Hello Rick, welcome to Seneschal", result
  end

  test "leaves unmatched variables as-is" do
    body = "Deploy ${branch} to ${env}"
    result = TemplateRenderer.new(body, { branch: "main" }).render
    assert_equal "Deploy main to ${env}", result
  end

  test "handles string keys in context" do
    body = "Task: ${task_title}"
    result = TemplateRenderer.new(body, { "task_title" => "Add auth" }).render
    assert_equal "Task: Add auth", result
  end

  test "handles empty context" do
    body = "No vars here"
    result = TemplateRenderer.new(body, {}).render
    assert_equal "No vars here", result
  end

  test "handles body with no variables" do
    body = "Plain text"
    result = TemplateRenderer.new(body, { unused: "value" }).render
    assert_equal "Plain text", result
  end

  test "handles empty body" do
    result = TemplateRenderer.new("", { key: "val" }).render
    assert_equal "", result
  end

  test "replaces multiple occurrences of same variable" do
    body = "${x} and ${x}"
    result = TemplateRenderer.new(body, { x: "hello" }).render
    assert_equal "hello and hello", result
  end

  # Schema-bound steps now leave their parsed payload in `run.context` as a
  # Hash. Before this fix, `${var}` interpolated `Hash#to_s` ("{\"a\"=>1}"),
  # which made the prompt unreadable and broke any downstream JSON parsing.
  test "renders Hash values as JSON, not Ruby's Hash#to_s" do
    body = "Config: ${cfg}"
    result = TemplateRenderer.new(body, { cfg: { "title" => "Driver Out!", "version" => 1 } }).render
    parsed = JSON.parse(result.delete_prefix("Config: "))
    assert_equal({ "title" => "Driver Out!", "version" => 1 }, parsed)
  end

  test "renders Array values as JSON" do
    body = "items=${items}"
    result = TemplateRenderer.new(body, { items: [{ "id" => 1 }, { "id" => 2 }] }).render
    parsed = JSON.parse(result.delete_prefix("items="))
    assert_equal([{ "id" => 1 }, { "id" => 2 }], parsed)
  end

  test "renders nil values as empty string" do
    body = "x=${x};y=${y}"
    result = TemplateRenderer.new(body, { x: nil, y: "set" }).render
    assert_equal "x=;y=set", result
  end
end
