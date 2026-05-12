namespace :seneschal do
  namespace :projects do
    desc "Reset each ready project's local_path to a clean default-branch checkout " \
         "so worktrees branch off a known-good state. Run once before enabling worktrees."
    task prepare_for_worktrees: :environment do
      require "open3"

      Project.where(repo_status: "ready").find_each do |project|
        unless project.local_path_exists?
          puts "skip   #{project.name}: local_path missing (#{project.local_path})"
          next
        end

        default_branch, _stderr, status = Open3.capture3(
          "git", "-C", project.local_path,
          "symbolic-ref", "--short", "refs/remotes/origin/HEAD"
        )
        if status.success?
          default_branch = default_branch.strip.delete_prefix("origin/")
        else
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
