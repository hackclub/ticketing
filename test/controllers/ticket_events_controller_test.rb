require "test_helper"

class TicketEventsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  def sign_in(user)
    get "/auth/developer/callback", params: { name: user.name, email: user.email }
  end

  def file(name = "note.txt", type = "text/plain")
    Rack::Test::UploadedFile.new(StringIO.new("hello"), type, original_filename: name)
  end

  test "the person a ticket is for can reply to the thread" do
    ticket = tickets(:website_bug)
    sign_in(users(:amber))

    assert_difference -> { ticket.events.comment.count }, 1 do
      post ticket_events_path(ticket), params: { ticket_event: { body: "Looking at it now" } }
    end

    assert_equal users(:amber), ticket.events.last.author
    assert ticket.events.last.comment?
  end

  test "the person who filed it can reply too" do
    ticket = tickets(:website_bug)
    sign_in(users(:requester))

    assert_difference -> { ticket.events.comment.count }, 1 do
      post ticket_events_path(ticket), params: { ticket_event: { body: "Any news?" } }
    end
  end

  test "somebody with nothing to do with the ticket can't" do
    ticket = tickets(:website_bug)
    sign_in(another_owner)

    assert_no_difference -> { ticket.events.count } do
      post ticket_events_path(ticket), params: { ticket_event: { body: "hello?" } }
    end

    assert_redirected_to root_path
  end

  test "a private note stays on this side" do
    ticket = tickets(:website_bug)
    sign_in(users(:amber))

    post ticket_events_path(ticket), params: { ticket_event: { body: "Chased ops" }, internal: "1" }

    assert ticket.events.last.internal_note?
  end

  test "a requester can't sneak a private note in" do
    ticket = tickets(:website_bug)
    sign_in(users(:requester))

    post ticket_events_path(ticket), params: { ticket_event: { body: "secret" }, internal: "1" }

    assert ticket.events.last.comment?
  end

  test "the requester never sees a private note" do
    ticket = tickets(:website_bug)
    ticket.events.create!(kind: :internal_note, body: "Privately annoyed about this", author: users(:amber))
    sign_in(users(:requester))

    get ticket_path(ticket)

    assert_response :success
    assert_no_match(/Privately annoyed about this/, response.body)
  end

  test "the person it's for does" do
    ticket = tickets(:website_bug)
    ticket.events.create!(kind: :internal_note, body: "Privately annoyed about this", author: users(:amber))
    sign_in(users(:amber))

    get ticket_path(ticket)

    assert_match "Privately annoyed about this", response.body
    assert_match "Private", response.body
  end

  test "a message can be nothing but a file" do
    ticket = tickets(:website_bug)
    sign_in(users(:requester))

    assert_difference -> { ticket.events.count }, 1 do
      post ticket_events_path(ticket), params: { ticket_event: { files: [ file("screenshot.png", "image/png") ] } }
    end

    assert_equal [ "screenshot.png" ], ticket.events.last.files.map { |f| f.filename.to_s }
  end

  test "an oversized file is refused with a readable reason" do
    ticket = tickets(:website_bug)
    sign_in(users(:requester))
    huge = Rack::Test::UploadedFile.new(StringIO.new("x" * (TicketEvent::MAX_FILE_SIZE + 1)), "text/plain",
                                        original_filename: "huge.log")

    assert_no_difference -> { ticket.events.count } do
      post ticket_events_path(ticket), params: { ticket_event: { body: "logs", files: [ huge ] } }
    end

    assert_match(/under/, flash[:alert])
  end

  test "an empty message with no file is refused" do
    ticket = tickets(:website_bug)
    sign_in(users(:amber))

    assert_no_difference -> { ticket.events.count } do
      post ticket_events_path(ticket), params: { ticket_event: { body: "  " } }
    end

    assert flash[:alert].present?
  end

  test "posting over turbo streams it in without a reload" do
    ticket = tickets(:website_bug)
    sign_in(users(:amber))

    post ticket_events_path(ticket), params: { ticket_event: { body: "Chased ops" } }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %(action="append" target="#{dom_id(ticket, :timeline)}"), response.body
    assert_match %(action="replace" target="#{dom_id(ticket, :composer)}"), response.body
    assert_match "Chased ops", response.body
  end

  test "you can delete your own, and not somebody else's" do
    ticket = tickets(:website_bug)
    mine = ticket.events.create!(body: "never mind", author: users(:requester))
    sign_in(users(:requester))

    assert_difference -> { ticket.events.count }, -1 do
      delete ticket_event_path(ticket, mine), as: :turbo_stream
    end
    assert_match %(action="remove" target="#{dom_id(mine)}"), response.body

    theirs = ticket.events.create!(body: "mine, actually", author: users(:amber))
    assert_no_difference -> { ticket.events.count } do
      delete ticket_event_path(ticket, theirs)
    end
  end

  test "a comment tells the other side, a private note tells nobody" do
    ticket = tickets(:website_bug)
    sign_in(users(:amber))

    assert_enqueued_emails 1 do
      post ticket_events_path(ticket), params: { ticket_event: { body: "On it" } }
    end

    assert_no_enqueued_emails do
      post ticket_events_path(ticket), params: { ticket_event: { body: "Privately annoyed" }, internal: "1" }
    end
  end

  test "the timeline goes away with its ticket" do
    ticket = tickets(:website_bug)
    ticket.events.create!(body: "gone soon", author: users(:amber))

    assert_difference -> { TicketEvent.count }, -1 do
      ticket.destroy
    end
  end
end
