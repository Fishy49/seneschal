class Comment < ApplicationRecord
  belongs_to :commentable, polymorphic: true
  belongs_to :user

  COMMENTABLE_TYPES = ["Run", "RunStep", "PipelineTask"].freeze
  MENTION_PATTERN = /@([a-zA-Z0-9._-]+)/

  validates :body, presence: true
  validates :commentable_type, inclusion: { in: COMMENTABLE_TYPES }

  scope :chronological, -> { order(created_at: :asc) }

  after_create_commit :broadcast_to_run
  after_create_commit :notify_mentioned
  after_create_commit :record_event

  # The run this comment hangs off, for deep links and broadcasts. Task
  # comments have none.
  def run
    case commentable
    when Run then commentable
    when RunStep then commentable.run
    end
  end

  # "@rick" matches rick@example.com and rick.cagle@hey.com: a token matches a
  # user when it equals the whole local part of their email, or that local
  # part's first dot / underscore / hyphen delimited segment. Nothing fuzzier,
  # so a mention is never a surprise. Self-mentions are ignored.
  def mentioned_users
    tokens = body.to_s.scan(MENTION_PATTERN).flatten.map(&:downcase).uniq
    return [] if tokens.empty?

    User.where.not(id: user_id).select do |candidate|
      local = candidate.email.to_s.split("@").first.to_s.downcase
      tokens.include?(local) || tokens.include?(local.split(/[.\-_]/).first)
    end
  end

  # Run and step comments share one feed on the run page, so they all land in
  # the same list; task comments keep a per-commentable thread.
  def dom_target
    run ? "run_discussion" : "comments_#{commentable_type.underscore}_#{commentable_id}"
  end

  private

  def record_event
    Event.record("comment.created", subject: self, user: user)
  end

  def broadcast_to_run
    target_run = run
    return unless target_run

    broadcast_append_later_to(target_run, target: dom_target, partial: "comments/comment",
                                          locals: { comment: self })
  rescue StandardError => e
    Rails.logger.error("Comment##{id} broadcast failed: #{e.class}: #{e.message}")
  end

  def notify_mentioned
    target_run = run
    return unless target_run && NotifyJob.configured?

    mentioned_users.each do |mentioned|
      NotifyJob.perform_later("comment.mentioned", target_run.id, {
                                "comment" => {
                                  "author" => user.email,
                                  "mentioned" => mentioned.email,
                                  "body" => body,
                                  "anchor" => anchor
                                }
                              })
    end
  rescue StandardError => e
    Rails.logger.error("Comment##{id} mention notification failed: #{e.class}: #{e.message}")
  end
end
