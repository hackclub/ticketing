require "test_helper"

class TicketsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  def sign_in(user)
    get "/auth/developer/callback", params: { name: user.name, email: user.email }
  end

  test "creating a ticket enqueues a notification email" do
    sign_in(users(:requester))

    assert_enqueued_emails 1 do
      post tickets_path, params: {
        ticket: {
          title: "Something is broken",
          service_id: services(:website).id,
          topic_id: topics(:bug).id,
          message: "Please help"
        }
      }
    end

    assert_redirected_to ticket_path(Ticket.last)
  end

  test "the index defaults to what is still open" do
    sign_in(users(:amber))
    closed = Ticket.create!(user: users(:requester), service: services(:website), topic: topics(:bug),
                            title: "Already finished", message: "x", status: :done)

    get tickets_path

    assert_response :success
    assert_match tickets(:website_bug).title, response.body
    assert_no_match(/Already finished/, response.body)
  end

  test "the closed tab shows done and won't-do together" do
    sign_in(users(:amber))
    done = Ticket.create!(user: users(:requester), service: services(:website), topic: topics(:bug),
                          title: "Shipped it", message: "x", status: :done)
    wont = Ticket.create!(user: users(:requester), service: services(:website), topic: topics(:bug),
                          title: "Not doing that", message: "x", status: :wont_do)

    get tickets_path(status: "closed")

    assert_match "Shipped it", response.body
    assert_match "Not doing that", response.body
    assert_no_match(/#{tickets(:website_bug).title}/, response.body)
  end

  test "a requester's index only has their own tickets" do
    sign_in(users(:requester))
    Ticket.create!(user: users(:amber), service: services(:slack), topic: topics(:access_request),
                   title: "Amber's own thing", message: "x", status: :done)

    get tickets_path(status: "all")

    assert_response :success
    assert_match tickets(:website_bug).title, response.body
    assert_no_match(/Amber's own thing/, response.body)
  end

  test "a made-up filter falls back to open rather than erroring" do
    sign_in(users(:requester))

    get tickets_path(status: "nonsense")

    assert_response :success
  end

  test "a non-owner cannot view someone else's ticket" do
    other_user = User.create!(sub: "sub_other", email: "other@example.com", name: "Other")
    sign_in(other_user)

    get ticket_path(tickets(:website_bug))

    assert_redirected_to root_path
  end

  test "the owner can view their own ticket" do
    sign_in(users(:requester))

    get ticket_path(tickets(:website_bug))

    assert_response :success
  end

  test "an admin can attach a note to a status change" do
    sign_in(users(:amber))
    ticket = tickets(:website_bug)

    patch ticket_path(ticket), params: { ticket: { status: "done", status_note: "Shipped this morning." } }

    ticket.reload
    assert ticket.done?
    assert_equal "Shipped this morning.", ticket.status_note
  end

  test "a status change without a note clears a stale one" do
    sign_in(users(:amber))
    ticket = tickets(:website_bug)
    ticket.update!(status_note: "An old note")

    patch ticket_path(ticket), params: { ticket: { status: "in_progress" } }

    assert_nil ticket.reload.status_note
  end

  test "changing status over turbo updates the page in place" do
    sign_in(users(:amber))
    ticket = tickets(:website_bug)

    patch ticket_path(ticket), params: { ticket: { status: "done", status_note: "Shipped." } }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    [ :status, :status_note, :status_form ].each do |part|
      assert_match %(action="replace" target="#{dom_id(ticket, part)}"), response.body
    end
    # The dashboard's queue is refreshed by the same response, so a ticket
    # that just closed drops out of it without a reload.
    assert_match %(action="replace" target="queue"), response.body
    assert_match "Shipped.", response.body
    assert ticket.reload.done?
  end

  test "a failed status change over turbo only reports the error" do
    sign_in(users(:amber))
    ticket = tickets(:website_bug)

    patch ticket_path(ticket), params: { ticket: { status: "nonsense" } }, as: :turbo_stream

    assert_response :success
    assert_match %(target="flash"), response.body
    assert_no_match(/target="queue"/, response.body)
  end

  test "status changes still work without turbo" do
    sign_in(users(:amber))
    ticket = tickets(:website_bug)

    patch ticket_path(ticket), params: { ticket: { status: "done" } }

    assert_response :redirect
    assert ticket.reload.done?
  end

  test "a non-admin cannot change a ticket's status" do
    sign_in(users(:requester))
    ticket = tickets(:website_bug)

    patch ticket_path(ticket), params: { ticket: { status: "done" } }

    refute ticket.reload.done?
  end
end
