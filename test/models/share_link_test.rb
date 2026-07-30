require "test_helper"

class ShareLinkTest < ActiveSupport::TestCase
  setup do
    @run = runs(:completed_run)
  end

  test "generates a long random token on create" do
    link = @run.share_links.create!
    assert link.token.present?
    assert_operator link.token.length, :>=, 32
  end

  test "tokens are unique across links" do
    tokens = Array.new(3) { @run.share_links.create!.token }
    assert_equal tokens.uniq, tokens
  end

  test "defaults to a thirty day lifetime" do
    link = @run.share_links.create!
    assert_in_delta ShareLink::DEFAULT_LIFETIME.from_now.to_i, link.expires_at.to_i, 5
    assert_not link.expired?
  end

  test "expired? reflects the expiry" do
    link = @run.share_links.create!(expires_at: 1.minute.ago)
    assert link.expired?
  end

  test "active scope excludes expired links" do
    live = @run.share_links.create!
    dead = @run.share_links.create!(expires_at: 1.day.ago)

    assert_includes ShareLink.active, live
    assert_not_includes ShareLink.active, dead
  end

  # to_param is deliberately left as the id: the public URL is always built
  # explicitly from the token, and an implicit url_for(link) must not mint a
  # shareable link by accident.
  test "to_param is the record id, not the token" do
    link = @run.share_links.create!
    assert_equal link.id.to_s, link.to_param
  end

  test "destroying the run destroys its links" do
    run = runs(:todo_run)
    run.share_links.create!
    assert_difference "ShareLink.count", -1 do
      run.destroy!
    end
  end

  test "deleting the creator keeps the link" do
    user = User.create!(email: "temp-share@test.com", password: "password12")
    link = @run.share_links.create!(created_by: user)

    user.destroy!
    assert ShareLink.exists?(link.id)
    assert_nil link.reload.created_by_id
  end
end
