require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  def sign_in(user)
    get "/auth/developer/callback", params: { name: user.name, email: user.email }
  end

  test "somebody with a queue sees how much is on it, in the nav and the tab" do
    users(:amber).tickets.create!(
      title: "Already started", message: "…", service: services(:website), topic: topics(:bug), status: :in_progress
    )
    sign_in(users(:amber))

    get root_path

    assert_response :success
    assert_select "title", "(2) Tickets"
    assert_select "#queue_badge a", text: "2"
    assert_select "#queue_badge a[title=?]", "1 open ticket, 1 in progress"
    assert_select "#queue_badge[data-favicon-open-value='1'][data-favicon-in-progress-value='1']"
    assert_match "1 open ticket, 1 in progress", response.body
  end

  test "an empty queue leaves the title alone and keeps the pill hidden for a later poll" do
    tickets(:website_bug).update!(status: :done)
    sign_in(users(:amber))

    get root_path

    assert_select "title", "Tickets"
    assert_select "#queue_badge a.hidden", text: "0"
  end

  test "the count is your own queue, not everyone's" do
    other = another_owner
    ticket_for(other, requester: users(:requester))
    ticket_for(other, requester: users(:requester))
    sign_in(other)

    get root_path

    assert_select "title", "(2) Tickets"
    assert_match "Everything on your plate", response.body

    sign_in(users(:amber))
    get root_path
    assert_select "title", "(1) Tickets"
  end

  test "somebody who takes no tickets has nothing to count" do
    sign_in(users(:requester))

    get root_path

    assert_select "title", "Tickets"
    assert_select "#queue_badge", false
  end

  test "changing a status sends the new count back with it" do
    sign_in(users(:amber))

    patch ticket_path(tickets(:website_bug)), params: { ticket: { status: "done" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_select "turbo-stream[action=replace][target=queue_badge]" do
      assert_select "a.hidden", text: "0"
    end
    assert_select "turbo-stream[action=replace][target=queue]" do
      assert_match "0 open tickets, 0 in progress", response.body
    end
  end
end
