require "open3"

class FileTreeWalker
  MAX_FILES = 5000
  MAX_FILE_SIZE = 100_000 # 100KB

  BINARY_EXTENSIONS = [
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".svg", ".webp", ".bmp", ".tiff",
    ".woff", ".woff2", ".ttf", ".eot", ".otf",
    ".pdf", ".zip", ".tar", ".gz", ".bz2", ".rar", ".7z",
    ".exe", ".dll", ".so", ".dylib", ".o", ".a",
    ".pyc", ".pyo", ".class", ".jar", ".war",
    ".min.js", ".min.css", ".bundle.js",
    ".lock", ".map", ".sqlite3", ".db", ".DS_Store"
  ].freeze

  def initialize(project)
    @project = project
    @repo_path = project.local_path
  end

  def call
    return { tree: [], file_count: 0, dir_count: 0 } unless File.directory?(@repo_path)

    raw_files = list_git_files
    entries = raw_files
              .reject { |f| binary?(f) }
              .first(MAX_FILES)
              .filter_map { |f| build_entry(f) }

    dirs = entries.pluck(:dir).uniq.sort

    { tree: entries, file_count: entries.size, dir_count: dirs.size }
  end

  def commit_sha
    stdout, _, status = Open3.capture3("git", "-C", @repo_path, "rev-parse", "HEAD")
    status.success? ? stdout.strip : nil
  end

  private

  def list_git_files
    stdout, _, status = Open3.capture3(
      "git", "-C", @repo_path, "ls-files", "--cached", "--others", "--exclude-standard"
    )
    return [] unless status.success?

    stdout.lines.map(&:strip).reject(&:empty?).sort
  end

  def binary?(path)
    ext = File.extname(path).downcase
    BINARY_EXTENSIONS.include?(ext) || path.include?("node_modules/") || path.include?("vendor/bundle/")
  end

  def build_entry(relative_path)
    full_path = File.join(@repo_path, relative_path)
    return nil unless File.exist?(full_path)

    size = File.size(full_path)
    return nil if size > MAX_FILE_SIZE

    {
      path: relative_path,
      type: "file",
      size: size,
      dir: File.dirname(relative_path),
      ext: File.extname(relative_path).delete_prefix(".")
    }
  end
end
