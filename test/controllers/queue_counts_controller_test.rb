require "test_helper"

class QueueCountsControllerTest < ActionDispatch::IntegrationTest
  def sign_in(user)
    get "/auth/developer/callback", params: { name: user.name, email: user.email }
  end

  test "answers with the signed-in person's queue" do
    users(:amber).tickets.create!(
      title: "Started", message: "…", service: services(:website), topic: topics(:bug), status: :in_progress
    )
    sign_in(users(:amber))

    get queue_count_path, headers: { "Accept" => "application/json" }

    assert_response :success
    assert_equal({ "open" => 1, "in_progress" => 1 }, response.parsed_body)
  end

  test "is zeros for somebody who takes no tickets" do
    sign_in(users(:requester))

    get queue_count_path, headers: { "Accept" => "application/json" }

    assert_equal({ "open" => 0, "in_progress" => 0 }, response.parsed_body)
  end

  test "refuses rather than redirects when signed out, so the poller can tell" do
    get queue_count_path, headers: { "Accept" => "application/json" }

    assert_response :unauthorized
    assert_nil session[:return_to]
  end
end
