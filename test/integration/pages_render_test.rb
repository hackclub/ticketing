require "test_helper"

# Every page, actually rendered. A route-helper typo or a bad view only shows
# up at render time, so each screen needs at least one request hitting it.
class PagesRenderTest < ActionDispatch::IntegrationTest
  def sign_in(user)
    get "/auth/developer/callback", params: { name: user.name, email: user.email }
  end

  test "the signed-out landing page renders" do
    get root_path

    assert_response :success
    assert_select "form[action=?]", "/auth/hackclub"
  end

  test "every page a requester can reach renders" do
    sign_in(users(:requester))

    [ root_path, new_ticket_path, ticket_path(tickets(:website_bug)), settings_path,
      tickets_path, tickets_path(status: "closed"), tickets_path(status: "all"), search_path ].each do |path|
      get path
      assert_response :success, "#{path} did not render"
    end
  end

  test "a ticket with a deadline and a blocker renders for both sides" do
    ticket = tickets(:website_bug)
    blocker = users(:amber).tickets.create!(
      title: "The thing it waits on", message: "…", service: services(:slack), topic: topics(:access_request)
    )
    ticket.update!(due_at: 2.days.ago)
    ticket.blocked_links.create!(blocker_ticket: blocker)

    sign_in(users(:amber))
    get ticket_path(ticket)
    assert_response :success
    assert_select "a[href=?]", ticket_path(blocker)

    sign_in(users(:requester))
    get ticket_path(ticket)
    assert_response :success
    # The requester is told they're waiting, not whose ticket it is.
    assert_select "a[href=?]", ticket_path(blocker), false
    assert_match "Waiting on 1 other ticket", response.body

    get root_path
    assert_response :success
  end

  test "the catch-all service is offered last on the new-ticket form" do
    other = Service.create!(name: "Other")
    other.topics.create!(name: "General Request")
    sign_in(users(:requester))

    get new_ticket_path

    assert_response :success
    options = css_select("#ticket_service_id option").map(&:text)
    assert_includes options, "Other"
    assert_equal "Other", options.last
  end

  test "every page an admin can reach renders" do
    sign_in(users(:amber))

    [
      root_path,
      new_ticket_path,
      ticket_path(tickets(:website_bug)),
      settings_path,
      admin_services_path,
      edit_admin_service_path(services(:website)),
      edit_admin_topic_path(topics(:bug)),
      admin_users_path,
      admin_user_path(users(:requester)),
      tickets_path,
      tickets_path(status: "closed"),
      search_path
    ].each do |path|
      get path
      assert_response :success, "#{path} did not render"
    end
  end

  test "a ticket page renders with a status note and a Slack requester" do
    users(:requester).update!(slack_id: "U123REQUESTER")
    tickets(:website_bug).update!(status_note: "Shipped this morning.")
    sign_in(users(:amber))

    get ticket_path(tickets(:website_bug))

    assert_response :success
    assert_match "Shipped this morning.", response.body
    assert_select "a[href*=?]", "slack.com/app_redirect?channel=U123REQUESTER"
  end
end
