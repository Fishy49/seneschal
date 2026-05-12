class SkillRepo < ApplicationRecord
  has_many :skills, dependent: :nullify

  # Subset of git's ref-name rules — strict enough to keep the branch out of
  # any argv-injection threat surface (no leading dashes, no shell metacharacters,
  # no ".." segments). See `git help check-ref-format` for the full ruleset; we
  # intentionally accept less than git allows.
  BRANCH_FORMAT = %r{\A[A-Za-z0-9_][A-Za-z0-9._/-]*\z}

  validates :name, presence: true, uniqueness: true
  validates :repo_url, presence: true
  validates :local_path, presence: true
  validates :branch, presence: true,
                     format: { with: BRANCH_FORMAT,
                               message: "may only contain letters, digits, dashes, underscores, dots, and slashes; " \
                                        "must not start with a dash" },
                     length: { maximum: 200 }
  validate :branch_has_no_double_dots
  validates :priority, numericality: { only_integer: true }

  before_validation :default_branch, on: :create
  before_validation :default_local_path, on: :create

  scope :enabled, -> { where(enabled: true) }
  scope :active_by_priority, -> { enabled.order(:priority, :created_at) }

  def self.compute_local_path(name)
    File.join(skill_repo_root, name.to_s.parameterize.presence || "repo-#{SecureRandom.hex(4)}")
  end

  def self.skill_repo_root
    Setting["skill_repo_root"].presence || Rails.root.join("storage/skill_repos").to_s
  end

  def cloned?
    File.directory?(File.join(local_path.to_s, ".git"))
  end

  def display_name
    name
  end

  # Returns true on success, false on failure. On failure the error is
  # stamped onto last_sync_error so the UI / logs can surface it.
  def sync!
    SkillRepoSyncer.new(self).call
  end

  def install_notes_for(skill_name)
    install_notes.is_a?(Hash) ? install_notes[skill_name.to_s] : nil
  end

  # Removes the cloned working directory, but ONLY if its expanded path lies
  # strictly inside the configured skill_repo_root. Refuses otherwise. This
  # guards against a malformed local_path (e.g. "/", "..", absolute paths
  # outside the root) ever reaching rm_rf — defense-in-depth for the
  # admin-only destroy/remove paths.
  def destroy_local_clone! # rubocop:disable Naming/PredicateMethod
    return false unless safe_local_path?
    return false unless File.directory?(local_path)

    FileUtils.rm_rf(local_path)
    true
  end

  def safe_local_path?
    return false if local_path.blank?

    resolved = File.expand_path(local_path)
    root = File.expand_path(self.class.skill_repo_root)
    return false if resolved == root || resolved == "/"

    resolved.start_with?("#{root}#{File::SEPARATOR}")
  end

  private

  def default_branch
    self.branch = "main" if branch.blank?
  end

  def branch_has_no_double_dots
    return if branch.blank?

    errors.add(:branch, "must not contain '..'") if branch.include?("..")
  end

  def default_local_path
    self.local_path = self.class.compute_local_path(name) if local_path.blank? && name.present?
  end
end
