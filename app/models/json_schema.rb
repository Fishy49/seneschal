class JsonSchema < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :body, presence: true
  validate :body_is_valid_json
  validate :body_is_valid_schema

  def referencing_steps
    Step.where("json_extract(config, '$.json_schema_id') = ?", id)
  end

  def parsed_body
    @parsed_body ||= JSON.parse(body)
  rescue JSON::ParserError
    nil
  end

  def schemer
    return nil unless parsed_body

    JSONSchemer.schema(parsed_body)
  end

  def validate_value(value)
    s = schemer
    return { valid: false, errors: ["Schema is invalid"] } unless s

    errors = s.validate(value).map do |err|
      pointer = err["data_pointer"].presence || "/"
      "#{pointer}: #{err["error"]}"
    end
    { valid: errors.empty?, errors: errors }
  end

  private

  def body_is_valid_json
    return if body.blank?

    JSON.parse(body)
  rescue JSON::ParserError => e
    errors.add(:body, "is not valid JSON: #{e.message}")
  end

  def body_is_valid_schema
    return if errors[:body].any?
    return if body.blank?

    JSONSchemer.schema(parsed_body)
  rescue StandardError => e
    errors.add(:body, "is not a valid JSON Schema: #{e.message}")
  end
end
