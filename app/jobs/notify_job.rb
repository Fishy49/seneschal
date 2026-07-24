require "net/http"

# Fire-and-forget outbound notification for the run lifecycle events a human
# would want to know about. Nothing here may ever affect a run: every failure
# is swallowed and logged, each destination is delivered independently, and
# the job is only enqueued when a destination is actually configured.
class NotifyJob < ApplicationJob
  queue_as :default

  EVENTS = [
    "run.awaiting_approval",
    "run.failed",
    "run.completed",
    "run.waiting_for_tokens",
    "comment.mentioned"
  ].freeze

  EVENT_LABELS = {
    "run.awaiting_approval" => "Needs approval",
    "run.failed" => "Run failed",
    "run.completed" => "Run completed",
    "run.waiting_for_tokens" => "Waiting for tokens",
    "comment.mentioned" => "You were mentioned"
  }.freeze

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 5

  # True when anything at all is listening, so callers can skip enqueueing.
  def self.configured?
    Setting["webhook_url"].present? || Setting["slack_webhook_url"].present?
  end

  # `extra` merges into the payload, carrying event-specific detail such as the
  # comment behind a comment.mentioned.
  def perform(event, run_id, extra = {})
    run = Run.includes(:pipeline_task, workflow: :project).find_by(id: run_id)
    return unless run

    extra = (extra || {}).deep_symbolize_keys

    # Independent rescues: a broken generic webhook must not cost the Slack
    # message, or the other way round.
    safely(event, run_id) { deliver(Setting["webhook_url"], payload_for(event, run).merge(extra)) }
    safely(event, run_id) { deliver(Setting["slack_webhook_url"], slack_payload_for(event, run, extra)) }
  end

  private

  def safely(event, run_id)
    yield
  rescue StandardError => e
    Rails.logger.error("NotifyJob(#{event}) failed for run #{run_id}: #{e.class}: #{e.message}")
  end

  def payload_for(event, run)
    {
      event: event,
      run: {
        id: run.id,
        status: run.status,
        url: run_url(run),
        task_title: run.pipeline_task&.title,
        project: run.workflow.project.name,
        workflow: run.workflow.name,
        started_by: run.started_by_label
      },
      timestamp: Time.current.iso8601
    }
  end

  # Slack Block Kit. Link buttons only: a true interactive approve/reject needs
  # a Slack app plus a signed callback endpoint, which is out of scope here.
  def slack_payload_for(event, run, extra = {})
    label = EVENT_LABELS.fetch(event, event)
    title = run.pipeline_task&.title || "Manual run"
    comment = extra[:comment]
    url = run_url(run)
    url = "#{url}##{comment[:anchor]}" if url && comment && comment[:anchor].present?

    blocks = [
      { type: "header", text: { type: "plain_text", text: "#{label}: #{title}".truncate(150) } },
      { type: "section",
        text: { type: "mrkdwn", text: "*Project:* #{run.workflow.project.name}\n*Run:* ##{run.id} (#{run.status})" } },
      { type: "context",
        elements: [{ type: "mrkdwn", text: "Workflow: #{run.workflow.name} - started by #{run.started_by_label}" }] }
    ]

    if comment
      blocks.insert(2, { type: "section",
                         text: { type: "mrkdwn", text: "*#{comment[:author]}:* #{comment[:body].to_s.truncate(2000)}" } })
    end

    if url
      button_text = event == "run.awaiting_approval" ? "Review & approve" : "View run"
      blocks << { type: "actions",
                  elements: [{ type: "button", text: { type: "plain_text", text: button_text }, url: url }] }
    end

    { text: "#{label}: #{title}", blocks: blocks }
  end

  # Absolute run URL, or nil when the operator has not told us what host the
  # app answers on. A nil url is better than a wrong one.
  def run_url(run)
    base = Setting["app_base_url"].to_s.strip
    return nil if base.blank?

    "#{base.chomp("/")}/runs/#{run.id}"
  end

  def deliver(url, payload)
    return if url.blank?

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
    request.body = payload.to_json
    http.request(request)
  end
end
