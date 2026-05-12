require "yaml"

# Parses an agentskills.io SKILL.md file into its YAML frontmatter and body.
#
# Frontmatter is delimited by `---` on its own line at the very start of the
# file and a matching `---` on its own line before the body. Anything before
# the opening fence, or a file with no fences at all, parses as body-only
# with an empty frontmatter hash.
#
# Returns a SkillMdParser::Result struct with `frontmatter` (Hash),
# `body` (String, with leading newline trimmed), and `raw` (the input).
class SkillMdParser
  Result = Data.define(:frontmatter, :body, :raw)

  FENCE_PATTERN = /\A---\s*\n(.*?)\n---\s*(?:\n|\z)/m

  def self.parse(content)
    new(content).parse
  end

  def initialize(content)
    @content = content.to_s
  end

  def parse
    if (match = @content.match(FENCE_PATTERN))
      frontmatter = parse_yaml(match[1])
      body = @content[match.end(0)..] || ""
      Result.new(frontmatter: frontmatter, body: body, raw: @content)
    else
      Result.new(frontmatter: {}, body: @content, raw: @content)
    end
  end

  private

  def parse_yaml(yaml_text)
    parsed = YAML.safe_load(yaml_text, permitted_classes: [Date, Time])
    parsed.is_a?(Hash) ? parsed : {}
  rescue Psych::SyntaxError
    {}
  end
end
