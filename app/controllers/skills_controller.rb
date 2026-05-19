class SkillsController < ApplicationController
  before_action :set_skill, only: [:show, :edit, :update, :destroy, :import_reference_schema]

  def index
    @skills = Skill.includes(:project).order(:name)
  end

  def show
    # Auto-refresh cached frontmatter when the file on disk has drifted from
    # what we cached last. Cheap when nothing changed (sha256 of SKILL.md vs
    # the stored content_hash); a no-op when the file is missing.
    return unless @skill.skill_md_path && File.exist?(@skill.skill_md_path)

    fresh_hash = @skill.compute_content_hash
    @skill.refresh_cached_metadata! if fresh_hash && fresh_hash != @skill.content_hash
  end

  def new
    @skill = Skill.new
  end

  def edit; end

  # Scaffolds a fresh SKILL.md directory on disk (via SkillScaffolder) and
  # creates the matching Skill row pointing at it. The form's `body` field
  # is the initial body content for the scaffolded file — there's no DB-only
  # path anymore. If the user picked a project scope, the skill lands under
  # `<project>/.seneschal/skills/<name>/`; shared skills land in the global
  # root (`SkillLoader.global_root`).
  def create
    attrs = create_params
    @skill = Skill.new(attrs.slice(:name, :description, :project_id,
                                   :default_json_schema_id, :default_output_variable))

    project = Project.find_by(id: attrs[:project_id])

    begin
      result = SkillScaffolder.call(
        name: attrs[:name],
        description: attrs[:description],
        body: attrs[:body],
        project: project
      )
    rescue SkillScaffolder::Error => e
      @skill.errors.add(:base, e.message)
      return render :new, status: :unprocessable_content
    end

    if result.already_existed
      @skill.errors.add(:base, "A SKILL.md already exists at #{result.skill_md_path}. " \
                               "Use Import or pick a different name.")
      return render :new, status: :unprocessable_content
    end

    @skill.source_kind = result.source_kind
    @skill.relative_path = result.relative_path

    if @skill.save
      @skill.refresh_cached_metadata!
      redirect_to @skill, notice: "Skill scaffolded at #{result.skill_md_path}."
    else
      # Persisting the AR row failed after we wrote the file — back the file
      # out so the next attempt doesn't trip the "already_existed" branch on
      # a half-created skill. SkillScaffolder.rollback enforces a path-
      # confinement check so this is safe even though `result.absolute_path`
      # ultimately derives from form input.
      SkillScaffolder.rollback(result)
      render :new, status: :unprocessable_content
    end
  end

  # Edit only mutates non-content fields. The skill's name, description, and
  # body live in SKILL.md on disk — the user edits those in their editor and
  # commits them with the project. The form for filesystem-backed skills no
  # longer exposes those fields; `refresh_cached_metadata!` re-pulls the
  # cached metadata from disk when invoked.
  def update
    if @skill.update(update_params)
      redirect_to @skill, notice: "Skill updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @skill.destroy
    redirect_to skills_path, notice: "Skill deleted."
  end

  # Imports a `references/<filename>.json` file as a top-level JsonSchema
  # row and sets it as the skill's default. Idempotent on schema name
  # (`<skill>__<basename>`): re-importing the same file overwrites the
  # row's body in place so on-disk edits propagate. Strips the file's
  # `$schema` keyword before persisting — the bundled `claude` CLI's
  # `--json-schema` flag only registers the StructuredOutput tool when
  # the schema either omits `$schema` or uses draft-07, and stripping it
  # is the safe-everywhere default (see #24's PR description).
  def import_reference_schema
    reference = params.expect(:reference)
    content = @skill.read_auxiliary_file("references", reference)

    return redirect_to(@skill, alert: "references/#{reference} not found.") if content.nil?

    begin
      body = JSON.parse(content)
    rescue JSON::ParserError => e
      return redirect_to(@skill, alert: "references/#{reference} is not valid JSON: #{e.message}")
    end

    body.delete("$schema") if body.is_a?(Hash)

    schema = JsonSchema.find_or_initialize_by(name: "#{@skill.name}__#{File.basename(reference, ".*").delete_suffix(".schema")}")
    schema.body = JSON.pretty_generate(body)
    schema.description = imported_schema_description(body, reference)

    if schema.save
      @skill.update!(
        default_json_schema_id: schema.id,
        default_output_variable: @skill.default_output_variable.presence ||
          File.basename(reference, ".*").delete_suffix(".schema")
      )
      redirect_to @skill, notice: "Imported references/#{reference} as default schema \"#{schema.name}\"."
    else
      redirect_to @skill, alert: "Schema validation failed: #{schema.errors.full_messages.join(", ")}"
    end
  end

  private

  def imported_schema_description(body, reference)
    return body["description"] if body.is_a?(Hash) && body["description"].present?
    return body["title"] if body.is_a?(Hash) && body["title"].present?

    "Imported from #{@skill.display_name} / references/#{reference}"
  end

  def set_skill
    @skill = Skill.find(params.expect(:id))
  end

  def create_params
    attrs = params.expect(
      skill: [:name, :description, :body, :scope, :default_json_schema_id, :default_output_variable]
    )
    normalize_schema_id!(attrs)
    apply_scope!(attrs)
    attrs
  end

  def update_params
    attrs = params.expect(
      skill: [:scope, :default_json_schema_id, :default_output_variable]
    )
    normalize_schema_id!(attrs)
    apply_scope!(attrs)
    attrs
  end

  def normalize_schema_id!(attrs)
    return unless attrs.key?(:default_json_schema_id)

    # Blank schema_id from the form arrives as "" (empty string). Normalize
    # to nil so the FK doesn't try to look up id=0 and AR clears it cleanly.
    attrs[:default_json_schema_id] = attrs[:default_json_schema_id].presence
  end

  def apply_scope!(attrs)
    return unless attrs.key?(:scope)

    scope = attrs.delete(:scope)
    attrs[:project_id] = case scope
                         when /\Aproject:(\d+)\z/
                           ::Regexp.last_match(1).to_i
                         end
  end
end
