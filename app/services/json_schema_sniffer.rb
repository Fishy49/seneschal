# Detects whether an arbitrary text blob looks like a JSON Schema document.
# Used by the Skill show page to decide whether to surface an "import as
# default schema" button next to a `references/*.json` file.
#
# Deliberately tolerant — false positives are easy to dismiss (the user
# just doesn't click the button), false negatives hide the affordance
# entirely. Any of the following is enough to qualify:
#   - top-level `$schema` keyword (a draft URI)
#   - top-level `properties` / `oneOf` / `anyOf` / `allOf` keyword
#   - `type: "object"` with a `properties` hash
class JsonSchemaSniffer
  HEURISTIC_KEYS = ["$schema", "properties", "oneOf", "anyOf", "allOf"].freeze

  def self.looks_like_schema?(content)
    return false if content.blank?

    parsed = JSON.parse(content)
    return false unless parsed.is_a?(Hash)

    HEURISTIC_KEYS.any? { |key| parsed.key?(key) } ||
      (parsed["type"] == "object" && parsed["properties"].is_a?(Hash))
  rescue JSON::ParserError
    false
  end
end
