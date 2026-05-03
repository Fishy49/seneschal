class JsonSchemaValidator
  def initialize(schema)
    @schema = schema
  end

  def validate(value)
    @schema.validate_value(value)
  end
end
