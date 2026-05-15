namespace :seneschal do
  namespace :skills do
    desc "Export every DB-backed Skill to an agentskills.io SKILL.md folder on disk. " \
         "Idempotent — re-running skips Skills that are already filesystem-backed. " \
         "Group-scoped Skills are skipped with a warning; migrate them by hand."
    task export_to_filesystem: :environment do
      stats = Hash.new(0)

      Skill.find_each do |skill|
        result = SkillExporter.call(skill)
        stats[result.status] += 1

        label = case result.status
                when :exported       then "exported"
                when :skipped        then "skipped (already exported)"
                when :skipped_group  then "skipped (group-scoped)"
                else result.status.to_s
                end
        line = "#{label.ljust(28)} #{skill.display_name}"
        line += "  → #{result.path}" if result.path
        puts line
      rescue StandardError => e
        stats[:error] += 1
        puts "error                         #{skill.display_name}: #{e.class}: #{e.message}"
      end

      puts
      puts "Summary:"
      stats.each { |status, count| puts "  #{status}: #{count}" }
    end
  end
end
