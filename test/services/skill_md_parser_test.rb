require "test_helper"

class SkillMdParserTest < ActiveSupport::TestCase
  test "parses YAML frontmatter and body separated by fences" do
    content = <<~MD
      ---
      name: ingest-feature
      description: Create a feature branch and PR
      ---
      # Body

      Do the thing.
    MD

    parsed = SkillMdParser.parse(content)
    assert_equal "ingest-feature", parsed.frontmatter["name"]
    assert_equal "Create a feature branch and PR", parsed.frontmatter["description"]
    assert_includes parsed.body, "# Body"
    assert_includes parsed.body, "Do the thing."
  end

  test "returns body-only with empty frontmatter when no fences are present" do
    content = "Just a plain prompt with no frontmatter."
    parsed = SkillMdParser.parse(content)
    assert_equal({}, parsed.frontmatter)
    assert_equal content, parsed.body
  end

  test "body --- inside markdown is not interpreted as a frontmatter closing fence" do
    content = <<~MD
      ---
      name: test
      description: d
      ---
      # Heading

      Some text with --- a horizontal rule.

      ---

      More text after the rule.
    MD

    parsed = SkillMdParser.parse(content)
    assert_equal "test", parsed.frontmatter["name"]
    assert_includes parsed.body, "Some text with --- a horizontal rule"
    assert_includes parsed.body, "More text after the rule"
  end

  test "malformed YAML returns empty frontmatter and falls back to whole content as body" do
    content = <<~MD
      ---
      name: ok
        bad indentation : value
      ---
      body here
    MD

    parsed = SkillMdParser.parse(content)
    assert_equal({}, parsed.frontmatter)
    # Body fallback still works
    assert_equal "body here\n", parsed.body
  end

  test "non-hash YAML root falls back to empty frontmatter" do
    content = "---\n- just\n- a\n- list\n---\nbody"
    parsed = SkillMdParser.parse(content)
    assert_equal({}, parsed.frontmatter)
  end

  test "frontmatter with extra fields keeps them intact" do
    content = <<~MD
      ---
      name: x
      description: y
      allowed-tools: Read,Edit
      version: 1.2.3
      author: someone
      ---
      body
    MD

    parsed = SkillMdParser.parse(content)
    assert_equal "Read,Edit", parsed.frontmatter["allowed-tools"]
    assert_equal "1.2.3", parsed.frontmatter["version"]
    assert_equal "someone", parsed.frontmatter["author"]
  end

  test "empty input returns empty result" do
    parsed = SkillMdParser.parse("")
    assert_equal({}, parsed.frontmatter)
    assert_equal "", parsed.body
    assert_equal "", parsed.raw
  end
end
