namespace :seneschal do
  namespace :skill_repos do
    desc "Register an external skill repo. " \
         "Usage: bin/rails 'seneschal:skill_repos:add[git@github.com:org/skills,my-skills,main]'"
    task :add, [:repo_url, :name, :branch] => :environment do |_t, args|
      repo_url = args[:repo_url] || ENV.fetch("URL", nil)
      name = args[:name] || ENV.fetch("NAME", nil) || infer_name(repo_url)
      branch = args[:branch] || ENV.fetch("BRANCH", "main")

      abort("usage: rake 'seneschal:skill_repos:add[<repo_url>,<name>,<branch>]'") if repo_url.blank?

      repo = SkillRepo.create!(name: name, repo_url: repo_url, branch: branch)
      puts "added  #{repo.name}  →  #{repo.repo_url}  (#{repo.branch})"
      puts "       will clone to #{repo.local_path}"
      puts
      puts "syncing now..."
      result = SkillRepoSyncer.new(repo).call
      if result.status == :ok
        puts "synced #{result.imported.size} skill(s): #{result.imported.join(", ")}"
      else
        puts "sync failed: #{result.error}"
      end
    end

    desc "List all registered skill repos with their sync status."
    task list: :environment do
      if SkillRepo.none?
        puts "(no skill repos registered)"
        next
      end

      SkillRepo.order(:priority, :created_at).each do |repo|
        status = repo.enabled? ? "enabled " : "disabled"
        last = repo.last_synced_at ? repo.last_synced_at.strftime("%Y-%m-%d %H:%M") : "never"
        line = "#{status}  pri=#{repo.priority}  #{repo.name.ljust(30)} synced=#{last}"
        line += "  ERROR: #{repo.last_sync_error.truncate(80)}" if repo.last_sync_error.present?
        puts line
      end
    end

    desc "Sync a single repo by name, or all enabled repos when called without args. " \
         "Usage: bin/rails 'seneschal:skill_repos:sync[my-skills]' or just :sync"
    task :sync, [:name] => :environment do |_t, args|
      target = args[:name] || ENV.fetch("NAME", nil)

      repos = if target.present?
                Array(SkillRepo.find_by(name: target)).tap do |list|
                  abort("no SkillRepo named #{target.inspect}") if list.empty?
                end
              else
                SkillRepo.enabled.to_a
              end

      repos.each do |repo|
        print "syncing #{repo.name}... "
        result = SkillRepoSyncer.new(repo).call
        if result.status == :ok
          archived_note = result.archived.any? ? " (archived: #{result.archived.size})" : ""
          puts "ok — #{result.imported.size} skill(s)#{archived_note}"
        else
          puts "FAIL: #{result.error}"
        end
      end
    end

    desc "Remove a SkillRepo registration. Also removes the cloned directory and its Skill records."
    task :remove, [:name] => :environment do |_t, args|
      name = args[:name] || ENV.fetch("NAME", nil)
      abort("usage: rake 'seneschal:skill_repos:remove[<name>]'") if name.blank?

      repo = SkillRepo.find_by(name: name) || abort("no SkillRepo named #{name.inspect}")
      Skill.where(skill_repo_id: repo.id).destroy_all
      FileUtils.rm_rf(repo.local_path) if File.directory?(repo.local_path)
      repo.destroy!
      puts "removed #{name}"
    end

    def infer_name(url)
      return nil if url.blank?

      base = url.split("/").last.to_s.delete_suffix(".git")
      base.presence || "skills-#{Time.current.to_i}"
    end
  end
end
