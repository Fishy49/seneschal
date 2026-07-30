# Broadcasts the roster of people watching a run. Deliberately its own stream
# rather than the run's Turbo stream, which carries HTML fragments.
class PresenceChannel < ApplicationCable::Channel
  def subscribed
    @run = Run.find_by(id: params[:run_id])
    return reject unless @run

    stream_from stream_name
    broadcast(presence.join(current_user.email))
  end

  def unsubscribed
    return unless @run

    broadcast(presence.leave(current_user.email))
  end

  private

  def stream_name = "presence:run:#{@run.id}"
  def presence = RunPresence.new(@run.id)

  def broadcast(viewers)
    ActionCable.server.broadcast(stream_name, { viewers: viewers })
  end
end
