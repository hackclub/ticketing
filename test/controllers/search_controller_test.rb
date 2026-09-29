require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  def sign_in(user)
    get "/auth/developer/callback", params: { name: user.name, email: user.email }
  end

  def ticket_for(user, title, message: "Details here.")
    user.tickets.create!(title: title, message: message, service: services(:website), topic: topics(:bug))
  end

  test "signed-out people get nothing" do
    get search_path, params: { q: "home" }

    assert_redirected_to root_path
  end

  test "straight to /search is a page you can use without the palette" do
    sign_in(users(:requester))

    get search_path

    assert_response :success
    assert_select "form[action=?] input[name=?]", search_path, "q"
  end

  test "the palette gets just the frame" do
    sign_in(users(:requester))

    get search_path, params: { q: "homepage" }, headers: { "Turbo-Frame" => "search_results" }

    assert_response :success
    assert_no_match(/<body/, response.body)
    assert_match "search_results", response.body
  end

  test "finds a ticket by title" do
    sign_in(users(:requester))

    get search_path, params: { q: "homepage" }

    assert_response :success
    assert_match tickets(:website_bug).title, response.body
  end

  test "finds a ticket by something said in the body" do
    sign_in(users(:requester))
    ticket_for(users(:requester), "Unrelated title", message: "the checkout page throws a 500")

    get search_path, params: { q: "checkout" }

    assert_match "Unrelated title", response.body
  end

  test "a requester only ever searches their own tickets" do
    sign_in(users(:requester))
    ticket_for(users(:amber), "Amber's secret plan")

    get search_path, params: { q: "secret" }

    assert_no_match(/Amber's secret plan/, response.body)
  end

  test "an admin searches everyone's" do
    sign_in(users(:amber))
    ticket_for(users(:requester), "Somebody else's problem")

    get search_path, params: { q: "somebody" }

    assert_match "Somebody else&#39;s problem", response.body
  end

  test "a ticket number jumps straight to that ticket" do
    sign_in(users(:requester))
    ticket = tickets(:website_bug)

    get search_path, params: { q: "##{ticket.id}" }

    assert_match ticket_path(ticket), response.body
    assert_match ticket.title, response.body
  end

  test "an admin can search for people" do
    sign_in(users(:amber))

    get search_path, params: { q: "requester" }

    assert_match admin_user_path(users(:requester)), response.body
  end

  test "a requester can't search for people" do
    sign_in(users(:requester))

    get search_path, params: { q: "amber" }

    assert_no_match(/admin\/users/, response.body)
  end

  test "an empty box offers somewhere to go" do
    sign_in(users(:requester))

    get search_path

    assert_response :success
    assert_match "Closed tickets", response.body
    assert_match new_ticket_path, response.body
  end

  test "admin-only destinations stay admin-only" do
    sign_in(users(:requester))

    get search_path, params: { q: "services" }

    assert_no_match(/Services &amp; topics/, response.body)
  end

  test "wildcards are treated as text, not as a search for everything" do
    sign_in(users(:requester))

    get search_path, params: { q: "%" }

    assert_response :success
    assert_no_match(/#{tickets(:website_bug).title}/, response.body)
  end
end
