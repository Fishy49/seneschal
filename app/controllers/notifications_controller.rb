class NotificationsController < ApplicationController
  # The Inbox's broom: everything unread becomes read in one motion.
  def read_all
    # rubocop:disable Rails/SkipsModelValidations -- bulk read-marking has no user input to validate
    current_user.notifications.unread.update_all(read_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
    redirect_back_or_to(root_path, notice: "Marked everything read.")
  end
end
