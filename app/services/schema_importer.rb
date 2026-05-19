# Imports a JSON Schema file living under a Skill's `references/` directory
# as a top-level `JsonSchema` row and (optionally) wires the skill's
# `default_json_schema_id` to it. Shared between SkillsController's manual
# "Import as default schema" button and SkillRepoSyncer's auto-import pass.
#
# Idempotent on the schema name (`<skill>__<basename-without-".schema">`):
# re-importing the same file overwrites the row's body in place so on-disk
# edits propagate.
#
# `set_default:` controls how aggressively the skill's default gets wired:
#   :always   — overwrite whatever default is there (used by the manual
#               button on the show page — the click IS the choice)
#   :if_blank — only when the skill currently has no default_json_schema_id
#               (syncer's single-schema case; never clobbers a manual pick)
#   :never    — only create / update the JsonSchema row; leave the skill's
#               default_json_schema_id untouched (syncer's multi-schema
#               case — too many candidates to auto-pick, so import them
#               all and let the operator wire one up via the show page)
class SchemaImporter
  Result = Data.define(:status, :schema, :reason)

  VALID_SET_DEFAULT_MODES = [:always, :if_blank, :never].freeze

  def self.call(**)
    new(**).call
  end

  def initialize(skill:, reference:, set_default: :always)
    @skill = skill
    @reference = reference
    @set_default = set_default
    raise ArgumentError, "set_default must be one of #{VALID_SET_DEFAULT_MODES.inspect}" \
      unless VALID_SET_DEFAULT_MODES.include?(@set_default)
  end

  def call
    content = @skill.read_auxiliary_file("references", @reference)
    return failure(:missing, "references/#{@reference} not found") if content.nil?

    begin
      body = JSON.parse(content)
    rescue JSON::ParserError => e
      return failure(:invalid_json, "references/#{@reference} is not valid JSON: #{e.message}")
    end

    body.delete("$schema") if body.is_a?(Hash)

    schema = JsonSchema.find_or_initialize_by(name: derive_name)
    schema.body = JSON.pretty_generate(body)
    schema.description = derive_description(body)

    return failure(:invalid_schema, schema.errors.full_messages.join(", ")) unless schema.save

    link_default(schema)
    Result.new(status: :imported, schema: schema, reason: nil)
  end

  private

  def derive_name
    "#{@skill.name}__#{File.basename(@reference, ".*").delete_suffix(".schema")}"
  end

  def derive_description(body)
    return body["description"] if body.is_a?(Hash) && body["description"].present?
    return body["title"] if body.is_a?(Hash) && body["title"].present?

    "Imported from #{@skill.display_name} / references/#{@reference}"
  end

  def link_default(schema)
    return if @set_default == :never
    return if @set_default == :if_blank && @skill.default_json_schema_id.present?

    @skill.update!(
      default_json_schema_id: schema.id,
      default_output_variable: @skill.default_output_variable.presence ||
        File.basename(@reference, ".*").delete_suffix(".schema")
    )
  end

  def failure(status, reason)
    Result.new(status: status, schema: nil, reason: reason)
  end
end
