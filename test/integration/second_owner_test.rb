require "test_helper"

# Everything that has to be true once Amber lets somebody else use the tracker:
# they run their own queue, and the two queues can't reach into each other.
class SecondOwnerTest < ActionDispatch::IntegrationTest
  def sign_in(user)
    get "/auth/developer/callback", params: { name: user.name, email: user.email }
  end

  setup do
    @owner = another_owner
    @service = @owner.services.first
    @topic = @service.topics.first
  end

  test "an admin switches somebody on from their profile page" do
    sign_in(users(:amber))
    person = users(:requester)

    patch admin_user_path(person), params: { user: { receives_tickets: "1" } }

    assert person.reload.receives_tickets?
    assert_equal [ "Other" ], person.services.map(&:name)
  end

  test "nobody else can switch themselves on" do
    sign_in(users(:requester))

    patch admin_user_path(users(:requester)), params: { user: { receives_tickets: "1" } }

    assert_redirected_to root_path
    refute users(:requester).reload.receives_tickets?
  end

  test "a ticket filed under their service is theirs to deal with" do
    sign_in(users(:requester))

    post tickets_path, params: {
      ticket: { title: "Please look at this", service_id: @service.id, topic_id: @topic.id, message: "Thanks!" }
    }

    ticket = Ticket.last
    assert_equal @owner, ticket.owner
    assert_equal users(:requester), ticket.user
  end

  test "they can triage what's filed to them" do
    ticket = ticket_for(@owner, requester: users(:requester))
    sign_in(@owner)

    patch ticket_path(ticket), params: { ticket: { status: "done", status_note: "Done!" } }

    assert ticket.reload.done?
  end

  test "they can't touch a ticket that isn't theirs" do
    sign_in(@owner)
    ticket = tickets(:website_bug)

    patch ticket_path(ticket), params: { ticket: { status: "done" } }

    assert_equal "open", ticket.reload.status
  end

  test "they can't read a ticket that isn't theirs either" do
    sign_in(@owner)

    get ticket_path(tickets(:website_bug))

    assert_redirected_to root_path
  end

  test "their dashboard is their own queue, not everyone's" do
    mine = ticket_for(@owner, requester: users(:requester), title: "Filed to Bo")
    sign_in(@owner)

    get root_path

    assert_response :success
    assert_match "Filed to Bo", response.body
    assert_no_match(/#{tickets(:website_bug).title}/, response.body)
  end

  test "the admin dashboard is Amber's own queue too" do
    ticket_for(@owner, requester: users(:requester), title: "Filed to Bo")
    sign_in(users(:amber))

    get root_path

    assert_match tickets(:website_bug).title, response.body
    assert_no_match(/Filed to Bo/, response.body)
  end

  test "the tickets index is Amber's own queue too, until she asks otherwise" do
    ticket_for(@owner, requester: users(:requester), title: "Filed to Bo")
    sign_in(users(:amber))

    get tickets_path(status: "all")

    assert_no_match(/Filed to Bo/, response.body)
    assert_match tickets(:website_bug).title, response.body
  end

  test "an admin can ask for everyone's, and only an admin gets it" do
    ticket_for(@owner, requester: users(:requester), title: "Filed to Bo")

    sign_in(users(:amber))
    get tickets_path(status: "all", scope: "everyone")
    assert_match "Filed to Bo", response.body
    assert_match tickets(:website_bug).title, response.body

    # Asking for it without being an admin changes nothing.
    sign_in(@owner)
    get tickets_path(status: "all", scope: "everyone")
    assert_match "Filed to Bo", response.body
    assert_no_match(/#{tickets(:website_bug).title}/, response.body)
  end

  test "the board and the search follow the same rule" do
    theirs = ticket_for(@owner, requester: users(:requester), title: "Filed to Bo")
    sign_in(users(:amber))

    get board_path
    assert_no_match(/Filed to Bo/, response.body)

    get board_path(scope: "everyone")
    assert_match "Filed to Bo", response.body

    # The term itself is echoed back either way, so look for the result.
    get search_path, params: { q: "Filed to Bo" }
    assert_no_match(/#{ticket_path(theirs)}/, response.body)

    get search_path, params: { q: "Filed to Bo", scope: "everyone" }
    assert_match ticket_path(theirs), response.body
  end

  test "a ticket you filed to somebody else isn't in your queue" do
    sign_in(users(:amber))
    mine = tickets(:website_bug)
    asked = ticket_for(@owner, requester: users(:amber), title: "Asked Bo for this")

    get tickets_path(status: "all")
    assert_match mine.title, response.body
    assert_no_match(/#{ticket_path(asked)}/, response.body)

    get board_path
    assert_no_match(/#{ticket_path(asked)}/, response.body)
  end

  test "but it is under what you filed" do
    sign_in(users(:amber))
    asked = ticket_for(@owner, requester: users(:amber), title: "Asked Bo for this")

    get tickets_path(scope: "filed", status: "all")

    assert_match "Asked Bo for this", response.body
    # That list is what you asked of other people, not your own queue.
    assert_no_match(/#{ticket_path(tickets(:website_bug))}/, response.body)
  end

  test "somebody who takes no tickets still sees what they filed" do
    sign_in(users(:requester))

    get tickets_path(status: "all")

    assert_response :success
    assert_match tickets(:website_bug).title, response.body
  end

  test "they manage their own services and nobody else's" do
    sign_in(@owner)

    get services_path

    assert_response :success
    assert_match "Other", response.body
    assert_no_match(/Website/, response.body)
  end

  test "they can't edit somebody else's service" do
    sign_in(@owner)

    get edit_service_path(services(:website))

    assert_response :not_found
  end

  test "somebody without a queue has no services page at all" do
    sign_in(users(:requester))

    get services_path

    assert_redirected_to root_path
  end

  test "the new-ticket form offers both people's services" do
    sign_in(users(:requester))

    get new_ticket_path

    assert_select "optgroup[label=?]", users(:amber).display_name
    assert_select "optgroup[label=?]", @owner.display_name
  end

  test "a switched-off person's services drop off the form" do
    @owner.stop_receiving_tickets!
    sign_in(users(:requester))

    get new_ticket_path

    assert_select "optgroup[label=?]", @owner.display_name, false
  end

  test "the search only reaches as far as their own queue" do
    ticket_for(@owner, requester: users(:requester), title: "Filed to Bo")
    sign_in(@owner)

    get search_path, params: { q: "e" }

    assert_match "Filed to Bo", response.body
    assert_no_match(/#{tickets(:website_bug).title}/, response.body)
  end
end
