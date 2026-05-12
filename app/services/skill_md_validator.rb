require "json_schemer"

# Validates parsed SKILL.md frontmatter against config/schemas/skill_md.schema.json.
# Returns a hash with :valid (bool) and :errors (array of human-readable strings).
class SkillMdValidator
  SCHEMA_PATH = Rails.root.join("config/schemas/skill_md.schema.json").freeze

  def self.validate(frontmatter)
    new(frontmatter).validate
  end

  def initialize(frontmatter)
    @frontmatter = frontmatter || {}
  end

  def self.schemer
    @schemer ||= JSONSchemer.schema(JSON.parse(File.read(SCHEMA_PATH)))
  end

  def validate
    errors = schemer.validate(@frontmatter).map { |e| format_error(e) }
    { valid: errors.empty?, errors: errors }
  end

  private

  def schemer
    self.class.schemer
  end

  def format_error(err)
    pointer = err["data_pointer"].to_s
    msg = err["error"] || err["type"] || "invalid"
    pointer.empty? ? msg : "#{pointer} #{msg}"
  end
end
