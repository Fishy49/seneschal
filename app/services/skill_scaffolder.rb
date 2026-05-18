require "fileutils"
require "yaml"

# Writes a starter SKILL.md to disk under the appropriate skills root and
# returns the resolved path + source_kind so the caller can persist the
# matching Skill record. Used by SkillsController#create (web UI) and
# db/seeds.rb so both paths land at the same filesystem shape and obey the
# same frontmatter contract.
#
# Scope → target:
#   project given             → <project.local_path>/.seneschal/skills/<name>/  (source_kind: "project_seneschal")
#   no project (shared)       → <SkillLoader.global_root>/<name>/               (source_kind: "global")
#   project_group given       → raises Error — group skills have no disk projection yet
#
# Frontmatter (`name`, `description`) is validated against the agentskills.io
# schema via SkillMdValidator before any disk write. Idempotent: if SKILL.md
# already exists at the target, returns a Result with `already_existed: true`
# and leaves the file untouched so seeders can re-run safely.
class SkillScaffolder
  Result = Data.define(:source_kind, :relative_path, :absolute_path, :skill_md_path, :already_existed)

  class Error < StandardError; end

  NAME_PATTERN = /\A[a-z][a-z0-9_-]*\z/

  def self.call(**)
    new(**).call
  end

  def initialize(name:, description:, body: nil, project: nil, project_group: nil)
    @name = name.to_s.strip
    @description = description.to_s.strip
    @body = body.to_s
    @project = project
    @project_group = project_group
  end

  def call
    raise Error, "Group-scoped skills have no on-disk location yet" if @project_group

    validate_name!
    validate_frontmatter!

    abs = absolute_path
    skill_md = File.join(abs, "SKILL.md")

    if File.exist?(skill_md)
      return Result.new(source_kind:, relative_path:, absolute_path: abs,
                        skill_md_path: skill_md, already_existed: true)
    end

    FileUtils.mkdir_p(abs)
    File.write(skill_md, render_skill_md)

    Result.new(source_kind:, relative_path:, absolute_path: abs,
               skill_md_path: skill_md, already_existed: false)
  end

  def source_kind
    @project ? "project_seneschal" : "global"
  end

  def relative_path
    @name
  end

  def absolute_path
    File.join(base_dir, relative_path)
  end

  private

  def base_dir
    if @project
      raise Error, "Project has no local_path; clone the repo first" if @project.local_path.blank?

      File.join(@project.local_path, ".seneschal", "skills")
    else
      SkillLoader.global_root
    end
  end

  def validate_name!
    raise Error, "Skill name is required" if @name.blank?
    raise Error, "Skill name must be kebab-case (start with a letter, digits/hyphens/underscores)" \
      unless @name.match?(NAME_PATTERN)
  end

  def validate_frontmatter!
    validation = SkillMdValidator.validate(frontmatter)
    return if validation[:valid]

    raise Error, "Invalid frontmatter — #{validation[:errors].join("; ")}"
  end

  def frontmatter
    { "name" => @name, "description" => @description }
  end

  def render_skill_md
    # Render frontmatter ourselves rather than via `to_yaml`. `Hash#to_yaml`
    # emits a leading `---` we'd have to strip, and the explicit form keeps
    # the file diff-friendly for humans editing on disk later.
    body_text = @body.presence ||
                "<!-- Author the skill's procedural body here. " \
                "Add scripts/ and references/ alongside SKILL.md as the skill grows. -->\n"
    <<~MD
      ---
      name: #{yaml_scalar(@name)}
      description: #{yaml_scalar(@description)}
      ---

      #{body_text}
    MD
  end

  # Quote scalar values that contain YAML-significant characters; otherwise
  # emit plain. Keeps simple skills' frontmatter readable while still safe
  # for descriptions with colons, quotes, multi-line content, etc.
  def yaml_scalar(value)
    str = value.to_s
    needs_quoting = str.match?(/[:#&*!|>'"%@`\n]/) || str.start_with?("-", "?", ",", "[", "]", "{", "}")
    if needs_quoting || str.empty?
      escaped = str.gsub("\\", "\\\\").gsub('"', '\\"').gsub("\n", '\\n')
      "\"#{escaped}\""
    else
      str
    end
  end
end
