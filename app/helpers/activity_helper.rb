module ActivityHelper
  EVENT_PHRASES = {
    "task.created" => "created task",
    "run.started" => "started run",
    "run.stopped" => "stopped run",
    "run.completed" => "completed run",
    "run.failed" => "run failed",
    "run.approved" => "approved a step on run",
    "run.rejected" => "rejected a step on run",
    "workflow.created" => "created workflow",
    "workflow.updated" => "updated workflow",
    "comment.created" => "commented on"
  }.freeze

  def event_phrase(event)
    EVENT_PHRASES.fetch(event.action, event.action)
  end

  # Best-effort link to whatever the event was about. Subjects can be deleted
  # after the fact, so every branch tolerates nil.
  def event_subject_link(event)
    subject = event.subject
    return tag.span("(deleted)", class: "text-content-muted") if subject.nil?

    case subject
    when Run then link_to("run ##{subject.id}", run_path(subject))
    when PipelineTask then link_to(subject.title, pipeline_task_path(subject))
    when Workflow then link_to(subject.name, project_workflow_path(subject.project, subject))
    when Comment then comment_subject_link(subject)
    else tag.span(subject.class.name.underscore.humanize, class: "text-content-muted")
    end
  end

  def comment_subject_link(comment)
    case comment.commentable
    when Run then link_to("run ##{comment.commentable.id}", run_path(comment.commentable))
    when RunStep then link_to("run ##{comment.commentable.run_id}", run_path(comment.commentable.run_id))
    when PipelineTask then link_to(comment.commentable.title, pipeline_task_path(comment.commentable))
    else tag.span("a deleted item", class: "text-content-muted")
    end
  end
end
