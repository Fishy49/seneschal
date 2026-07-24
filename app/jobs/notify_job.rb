require "net/http"

# Fire-and-forget outbound notification for the run lifecycle events a human
# would want to know about. Nothing here may ever affect a run: every failure
# is swallowed and logged, and the job is only enqueued when a destination is
# actually configured.
class NotifyJob < ApplicationJob
  queue_as :default

  EVENTS = [
    "run.awaiting_approval",
    "run.failed",
    "run.completed",
    "run.waiting_for_tokens"
  ].freeze

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 5

  # True when anything at all is listening, so callers can skip enqueueing.
  def self.configured?
    Setting["webhook_url"].present?
  end

  def perform(event, run_id)
    run = Run.includes(:pipeline_task, workflow: :project).find_by(id: run_id)
    return unless run

    deliver(Setting["webhook_url"], payload_for(event, run))
  rescue StandardError => e
    Rails.logger.error("NotifyJob(#{event}) failed for run #{run_id}: #{e.class}: #{e.message}")
  end

  private

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
