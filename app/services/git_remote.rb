require "open3"

# Thin wrapper around `git ls-remote` so we can list branches and read the
# HEAD SHA of a branch without cloning. Uses whatever auth the host's git
# already has (SSH keys, credential helpers) so private repos "just work"
# with the same setup that CloneRepoJob relies on.
class GitRemote
  TIMEOUT_SECONDS = 15

  class Error < StandardError; end

  def self.branches(repo_url)
    out = run!("ls-remote", "--heads", repo_url)
    out.each_line.filter_map do |line|
      _sha, ref = line.strip.split(/\s+/, 2)
      next unless ref&.start_with?("refs/heads/")

      ref.sub("refs/heads/", "")
    end.sort
  end

  def self.head_sha(repo_url, branch)
    out = run!("ls-remote", repo_url, "refs/heads/#{branch}")
    line = out.lines.first
    return nil if line.blank?

    line.strip.split(/\s+/).first
  end

  def self.run!(*args)
    out, err, status = Open3.capture3("git", *args)
    raise Error, err.strip.presence || "git #{args.first} failed" unless status.success?

    out
  end
end
