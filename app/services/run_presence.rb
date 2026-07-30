# Who currently has a given run open. Backed by the Rails cache (SolidCache in
# production) rather than process memory so the roster survives more than one
# web worker.
#
# Viewers are counted, not merely listed, so closing one of two tabs does not
# make the whole person disappear from everyone else's view.
class RunPresence
  TTL = 1.hour

  def initialize(run_id)
    @run_id = run_id
  end

  def join(viewer) = adjust(viewer, 1)
  def leave(viewer) = adjust(viewer, -1)
  def viewers = roster.keys.sort

  private

  def cache_key = "presence/run/#{@run_id}"
  def roster = Rails.cache.read(cache_key) || {}

  def adjust(viewer, delta)
    current = roster
    count = current.fetch(viewer, 0) + delta

    if count.positive?
      current[viewer] = count
    else
      current.delete(viewer)
    end

    Rails.cache.write(cache_key, current, expires_in: TTL)
    current.keys.sort
  end
end
