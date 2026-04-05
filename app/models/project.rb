class Project < ApplicationRecord
  has_many :workflows, dependent: :destroy
  has_many :runs, through: :workflows
  has_many :skills, dependent: :destroy
  has_many :pipeline_tasks, dependent: :destroy

  REPO_STATUSES = %w[not_cloned cloning ready error].freeze

  validates :name, presence: true, uniqueness: true
  validates :repo_url, presence: true
  validates :local_path, presence: true
  validates :repo_status, presence: true, inclusion: { in: REPO_STATUSES }
  validate :ensure_local_path_exists, if: -> { local_path.present? }

  before_save :detect_repo_status, if: -> { local_path_changed? || new_record? }

  def repo_ready?
    repo_status == "ready"
  end

  def repo_nwo
    match = repo_url.match(%r{[:/]([^/]+)/([^/]+?)(?:\.git)?$})
    match ? "#{match[1]}/#{match[2]}" : nil
  end

  def repo_owner
    repo_nwo&.split("/")&.first
  end

  def repo_name
    repo_nwo&.split("/")&.last
  end

  private

  def detect_repo_status
    if local_path.present? && File.exist?(File.join(local_path, ".git"))
      self.repo_status = "ready"
    end
  end

  def ensure_local_path_exists
    path = Pathname.new(local_path)
    return if path.directory?

    FileUtils.mkdir_p(path)
  rescue Errno::EACCES
    errors.add(:local_path, "could not be created: permission denied")
  rescue SystemCallError => e
    errors.add(:local_path, "could not be created: #{e.message}")
  end
end
