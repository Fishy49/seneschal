# A run's thread mixes three record types; each brings its own partial. The
# same partials render from broadcast jobs, so none of them may touch
# controller state like current_user.
module ThreadHelper
  def render_thread_item(item)
    case item
    when Comment then render("comments/comment", comment: item)
    when ApprovalEvent then render("approval_events/thread_seal", approval_event: item)
    when Event then render("events/thread_event", event: item)
    end
  end

  # Thread rows show people the way comments do: by the email's local part.
  def thread_actor(user)
    user ? user.email.split("@").first : "system"
  end
end
