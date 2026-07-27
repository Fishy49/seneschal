module JsonSchemasHelper
  # Prefilled into a new schema so nobody starts at an empty box.
  STARTER_BODY = <<~JSON.freeze
    {
      "type": "object",
      "properties": {
        "summary": { "type": "string" },
        "files_changed": { "type": "array", "items": { "type": "string" } }
      },
      "required": ["summary"]
    }
  JSON

  # "3 steps · 2 skills", omitting whichever is zero, and saying so when both
  # are.
  def schema_usage_label(step_count, skill_count)
    parts = []
    parts << pluralize(step_count, "step") if step_count.positive?
    parts << pluralize(skill_count, "skill") if skill_count.positive?
    parts.any? ? parts.join(" · ") : "unused"
  end
end
