require "test_helper"

class ShareLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
    @run = runs(:completed_run)
  end

  test "POST create mints a link attributed to the current user" do
    assert_difference "ShareLink.count", 1 do
      post share_links_path(run_id: @run.id)
    end

    link = ShareLink.last
    assert_equal users(:admin), link.created_by
    assert_equal @run, link.run
    assert_redirected_to run_path(@run)
    assert_match link.token, flash[:notice]
  end

  test "DELETE destroy revokes the link" do
    link = @run.share_links.create!
    assert_difference "ShareLink.count", -1 do
      delete share_link_path(link)
    end
    assert_redirected_to run_path(@run)
  end

  test "the run page lists existing links with a revoke button" do
    link = @run.share_links.create!
    get run_path(@run)
    assert_response :success
    assert_match link.token, response.body
    assert_select "form[action=?]", share_link_path(link)
  end

  test "requires authentication" do
    delete logout_path
    assert_no_difference "ShareLink.count" do
      post share_links_path(run_id: @run.id)
    end
    assert_redirected_to login_path
  end
end
