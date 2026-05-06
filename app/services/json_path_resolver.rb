class JsonPathResolver
  # Resolves dotted-path lookups against the run context. Only supports object
  # property paths (e.g. "pr_review.summary.title") — no array indexing or
  # wildcards. The first segment names a context variable; subsequent segments
  # walk into the parsed JSON value.
  #
  # Returns:
  #   - the resolved value (Hash/Array/scalar) when the path resolves
  #   - the raw value when the path has no dots and the variable exists
  #   - nil when the variable is missing, the parent isn't valid JSON, or any
  #     segment doesn't exist
  def self.lookup(context, path)
    return nil if context.nil? || path.to_s.empty?

    head, *rest = path.to_s.split(".")
    value = context[head] || context[head.to_s] || context[head.to_sym]
    return value if rest.empty?
    return nil if value.nil?

    parsed = parse_value(value)
    return nil if parsed.nil?

    rest.reduce(parsed) do |node, key|
      return nil unless node.is_a?(Hash)

      node[key] || node[key.to_sym]
    end
  end

  def self.parse_value(value)
    return value if value.is_a?(Hash) || value.is_a?(Array)

    JSON.parse(value.to_s)
  rescue JSON::ParserError
    nil
  end
  private_class_method :parse_value

  # Formats a resolved value for injection into a prompt or interpolation.
  # Strings/numbers/booleans pass through; objects and arrays get JSON-encoded.
  def self.format(value)
    case value
    when nil then ""
    when String, Numeric, TrueClass, FalseClass then value.to_s
    else JSON.pretty_generate(value)
    end
  end

  # Walks a JSON Schema body and yields every property path. Descends into
  # nested objects (`type: "object"` with `properties`) but never into array
  # items. Intermediate object paths are included so callers can pick whole
  # sub-trees as well as leaves.
  def self.paths_for_schema(schema_body, prefix: nil)
    body = schema_body.is_a?(String) ? JSON.parse(schema_body) : schema_body
    out = []
    walk_schema(body, Array(prefix), out)
    out
  rescue JSON::ParserError
    []
  end

  def self.walk_schema(node, prefix, out)
    return unless node.is_a?(Hash)

    props = node["properties"]
    return unless props.is_a?(Hash)

    props.each do |key, sub|
      path = prefix + [key]
      out << path.join(".")
      walk_schema(sub, path, out) if sub.is_a?(Hash) && sub["type"] == "object"
    end
  end
  private_class_method :walk_schema
end
