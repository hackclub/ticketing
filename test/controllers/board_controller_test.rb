require "test_helper"

class BoardControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  def sign_in(user)
    get "/auth/developer/callback", params: { name: user.name, email: user.email }
  end

  test "a column per status, each holding its own tickets" do
    sign_in(users(:amber))
    done = Ticket.create!(user: users(:requester), service: services(:website), topic: topics(:bug),
                          title: "Already finished", message: "x", status: :done)

    get board_path

    assert_response :success
    Ticket.statuses.each_key { |status| assert_select "[data-status=?]", status }
    assert_match dom_id(tickets(:website_bug), :card), response.body
    assert_match dom_id(done, :card), response.body
  end

  test "you can drag what's yours" do
    sign_in(users(:amber))

    get board_path

    assert_select "##{dom_id(tickets(:website_bug), :card)}[draggable]"
  end

  test "you can't drag somebody else's" do
    sign_in(users(:requester))

    get board_path

    assert_select "##{dom_id(tickets(:website_bug), :card)}"
    assert_select "##{dom_id(tickets(:website_bug), :card)}[draggable]", false
  end

  test "the board only shows what you're allowed to see" do
    owner = another_owner
    theirs = ticket_for(owner, title: "Not yours")
    sign_in(users(:requester))

    get board_path

    assert_no_match(/Not yours/, response.body)
    assert_no_match(/#{dom_id(theirs, :card)}/, response.body)
  end

  test "dropping a card is an ordinary status change" do
    sign_in(users(:amber))
    ticket = tickets(:website_bug)

    patch ticket_path(ticket), params: { ticket: { status: "in_progress" } }, as: :turbo_stream

    assert_response :success
    assert ticket.reload.in_progress?
  end

  test "finished columns are capped" do
    sign_in(users(:amber))
    (BoardController::CLOSED_SHOWN + 3).times do |n|
      Ticket.create!(user: users(:requester), service: services(:website), topic: topics(:bug),
                     title: "Done #{n}", message: "x", status: :done)
    end

    get board_path

    assert_equal BoardController::CLOSED_SHOWN, response.body.scan(/board-card/).size - 1
  end
end
