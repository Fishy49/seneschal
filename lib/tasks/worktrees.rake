namespace :seneschal do
  namespace :projects do
    desc "Reset each ready project's local_path to a clean default-branch checkout. " \
         "Optional: WorktreeManager.allocate branches off origin/HEAD directly, so it " \
         "doesn't care what state local_path is in. Useful as a cleanup tool for hosts " \
         "that ran the legacy single-tree model and want local_path normalized for the " \
         "out-of-band consumers (CLAUDE.md reading, code maps, context_projects)."
    task prepare_for_worktrees: :environment do
      require "open3"

      Project.where(repo_status: "ready").find_each do |project|
        unless project.local_path_exists?
          puts "skip   #{project.name}: local_path missing (#{project.local_path})"
          next
        end
        # Defensive: `git -C <path>` walks UP if <path> isn't a git repo,
        # potentially acting on a parent repo by accident. Require .git/.
        unless File.exist?(File.join(project.local_path, ".git"))
          puts "skip   #{project.name}: no .git at #{project.local_path}"
          next
        end

        default_branch = WorktreeManager.default_branch_name(project)
        if default_branch.nil?
          default_branch = "main"
          puts "warn   #{project.name}: could not detect default branch, falling back to main"
        end

        _, checkout_err, checkout_status = Open3.capture3(
          "git", "-C", project.local_path, "checkout", default_branch
        )
        unless checkout_status.success?
          puts "fail   #{project.name}: checkout #{default_branch} failed: #{checkout_err.strip}"
          next
        end

        _, pull_err, pull_status = Open3.capture3(
          "git", "-C", project.local_path, "pull", "--ff-only"
        )
        puts "warn   #{project.name}: pull --ff-only failed: #{pull_err.strip}" unless pull_status.success?

        puts "ready  #{project.name}: on #{default_branch}"
      end
    end

    desc "Clean up every git worktree allocated by Seneschal, regardless of retention age. " \
         "Useful after a botched migration or a host crash that left stale worktrees behind."
    task reap_all_worktrees: :environment do
      Run.where.not(worktree_path: nil).find_each do |run|
        WorktreeManager.cleanup(run)
        puts "cleaned run ##{run.id}"
      rescue StandardError => e
        puts "fail run ##{run.id}: #{e.class}: #{e.message}"
      end
    end
  end
end
