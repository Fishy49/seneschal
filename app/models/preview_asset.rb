class PreviewAsset < ApplicationRecord
  belongs_to :run_step
  belongs_to :run

  KINDS = ["image", "audio", "video"].freeze

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :original_filename, presence: true
  validates :storage_path, presence: true
  validates :byte_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:created_at, :id) }

  # Persistent root that bin/seneschal-asset writes into and the controller
  # serves out of. Worktrees can be reaped at any time, so assets are copied
  # here at registration so old runs stay browsable.
  def self.assets_root
    Setting["run_assets_root"].presence&.then { |p| Pathname.new(p) } ||
      Rails.root.join("storage/run_assets")
  end

  def absolute_path
    Pathname.new(storage_path).absolute? ? Pathname.new(storage_path) : self.class.assets_root.join(storage_path)
  end

  def file_exists?
    File.exist?(absolute_path)
  end

  def display_label
    label.presence || original_filename
  end
end
