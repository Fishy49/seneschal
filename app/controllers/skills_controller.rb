class SkillsController < ApplicationController
  before_action :set_skill, only: [:show, :edit, :update, :destroy]

  def index
    @skills = Skill.includes(:project, :project_group).order(:name)
    @project_groups = ProjectGroup.ordered
    return if params[:group_id].blank?

    @skills = if params[:group_id] == "none"
                @skills.where(project_group_id: nil)
              else
                @skills.where(project_group_id: params[:group_id])
              end
  end

  def show
    # Auto-refresh cached frontmatter when the file on disk has drifted from
    # what we cached last. Cheap when nothing changed (sha256 of SKILL.md vs
    # the stored content_hash); a no-op for legacy DB-only Skills.
    return unless @skill.filesystem_backed?
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
    @skill = Skill.new(attrs.slice(:name, :description, :project_id, :project_group_id,
                                   :default_json_schema_id, :default_output_variable))

    project = Project.find_by(id: attrs[:project_id])
    project_group = ProjectGroup.find_by(id: attrs[:project_group_id])

    begin
      result = SkillScaffolder.call(
        name: attrs[:name],
        description: attrs[:description],
        body: attrs[:body],
        project: project,
        project_group: project_group
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
      # a half-created skill.
      FileUtils.rm_rf(result.absolute_path)
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

  private

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
    case scope
    when /\Agroup:(\d+)\z/
      attrs[:project_group_id] = ::Regexp.last_match(1).to_i
      attrs[:project_id] = nil
    when /\Aproject:(\d+)\z/
      attrs[:project_id] = ::Regexp.last_match(1).to_i
      attrs[:project_group_id] = nil
    else
      attrs[:project_id] = nil
      attrs[:project_group_id] = nil
    end
  end
end
