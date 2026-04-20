require "test_helper"

class AssistantToolCatalogTest < ActiveSupport::TestCase
  test "markdown returns a non-empty string" do
    result = AssistantToolCatalog.markdown
    assert_kind_of String, result
    assert result.length.positive?
  end

  test "markdown includes key API endpoints" do
    result = AssistantToolCatalog.markdown
    assert_includes result, "/projects"
    assert_includes result, "/skills"
    assert_includes result, "/workflows"
    assert_includes result, "/steps"
    assert_includes result, "/pipeline_tasks"
    assert_includes result, "ui/ask_choices"
    assert_includes result, "ui/ask_text"
    assert_includes result, "ui/navigate"
  end

  test "markdown includes authentication instructions" do
    result = AssistantToolCatalog.markdown
    assert_includes result, "ASSISTANT_API_TOKEN"
    assert_includes result, "ASSISTANT_API_BASE"
    assert_includes result, "Authorization: Bearer"
  end
end
