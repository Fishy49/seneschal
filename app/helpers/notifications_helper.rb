module NotificationsHelper
  # Where clicking an inbox row lands. Contexts can be deleted after the
  # fact; the Activity page is the graceful fallback.
  def notification_target_path(notification)
    case notification.context
    when Run then run_path(notification.context)
    when PipelineTask then pipeline_task_path(notification.context)
    else activity_path
    end
  end

  def notification_context_title(notification)
    case notification.context
    when Run then run_display_name(notification.context)
    when PipelineTask then notification.context.title
    else "a deleted item"
    end
  end
end
