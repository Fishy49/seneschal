class SkillRepo < ApplicationRecord
  has_many :skills, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :repo_url, presence: true
  validates :local_path, presence: true
  validates :branch, presence: true
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

  private

  def default_branch
    self.branch = "main" if branch.blank?
  end

  def default_local_path
    self.local_path = self.class.compute_local_path(name) if local_path.blank? && name.present?
  end
end
