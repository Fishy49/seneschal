require "yaml"
require "fileutils"

# Exports a legacy DB-backed Skill to an agentskills.io SKILL.md folder on
# disk and stamps the Skill record with source_kind + relative_path so it
# resolves through the filesystem path on subsequent reads.
#
# Target locations:
#   - shared skill (no project, no group):
#       <SkillLoader.global_root>/<slug>/SKILL.md
#       source_kind = "global"
#   - project-scoped skill:
#       <project.local_path>/.seneschal/skills/<slug>/SKILL.md
#       source_kind = "project_seneschal"
#   - group-scoped skill:
#       SKIPPED — there's no single project to attach to, and exporting to
#       each member of the group would create N copies that drift. Operators
#       can hand-migrate group skills if they really want them on disk.
#
# Idempotent: if the Skill is already filesystem_backed and its SKILL.md
# exists on disk, the exporter is a no-op (returns :skipped). The Skill's
# `body` column is intentionally NOT cleared during transition — that's the
# C3 migration's job once everyone's exported.
class SkillExporter
  Result = Data.define(:status, :reason, :path)

  def self.call(skill)
    new(skill).call
  end

  def initialize(skill)
    @skill = skill
  end

  def call
    return Result.new(status: :skipped_group, reason: "group-scoped", path: nil) if @skill.group_scoped?

    target = target_dir
    skill_md = File.join(target, "SKILL.md")

    return Result.new(status: :skipped, reason: "already exported", path: skill_md) if @skill.filesystem_backed? && File.exist?(skill_md)

    FileUtils.mkdir_p(target)
    File.write(skill_md, render_skill_md)

    @skill.update!(source_kind: source_kind, relative_path: slug)
    @skill.refresh_cached_metadata!

    Result.new(status: :exported, reason: nil, path: skill_md)
  end

  private

  # agentskills.io slugs are kebab-case. Convert underscores to dashes first
  # so existing names like `ingest_feature` end up as `ingest-feature`.
  def slug
    @slug ||= @skill.name.to_s.tr("_", "-").parameterize.presence ||
              "skill-#{@skill.id}"
  end

  def source_kind
    @skill.project_id.present? ? "project_seneschal" : "global"
  end

  def target_dir
    if @skill.project_id.present?
      File.join(@skill.project.local_path, ".seneschal", "skills", slug)
    else
      File.join(SkillLoader.global_root, slug)
    end
  end

  def render_skill_md
    frontmatter_yaml = YAML.dump(frontmatter).sub(/\A---\n?/, "").rstrip
    body = legacy_body.to_s
    body = "#{body}\n" unless body.empty? || body.end_with?("\n")
    "---\n#{frontmatter_yaml}\n---\n\n#{body}"
  end

  # Reads from the DB column directly so we get the legacy body even after the
  # Skill is marked filesystem-backed (Skill#body would otherwise read from disk).
  def legacy_body
    @skill.read_attribute(:body)
  end

  def frontmatter
    fm = {
      "name" => slug,
      "description" => @skill.description.presence ||
                       "(TODO) When should an agent use the #{slug} skill?"
    }
    tools = inferred_allowed_tools
    fm["allowed-tools"] = tools if tools
    fm
  end

  # Picks the most common allowed_tools string across Steps that reference
  # this Skill. Returns nil if no Step has a custom allowed_tools, in which
  # case the SKILL.md just inherits StepExecutor's default at execution time.
  def inferred_allowed_tools
    tools = @skill.steps.filter_map { |s| s.config["allowed_tools"].presence }
    return nil if tools.empty?

    tools.tally.max_by { |_value, count| count }.first
  end
end
