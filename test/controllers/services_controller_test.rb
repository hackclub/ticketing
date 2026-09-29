require "test_helper"

class ServicesControllerTest < ActionDispatch::IntegrationTest
  def sign_in(user)
    get "/auth/developer/callback", params: { name: user.name, email: user.email }
  end

  test "non-admins can't reach the taxonomy page" do
    sign_in(users(:requester))

    get services_path

    assert_redirected_to root_path
  end

  test "the page lists every service with its topics nested underneath" do
    sign_in(users(:amber))

    get services_path

    assert_response :success
    assert_match services(:website).name, response.body
    assert_match topics(:bug).name, response.body
    assert_match services(:slack).name, response.body
    assert_match topics(:access_request).name, response.body
  end

  test "retired services and topics are marked as such" do
    services(:slack).update!(active: false)
    topics(:bug).update!(active: false)
    sign_in(users(:amber))

    get services_path

    assert_select "span", text: "retired", count: 2
  end

  test "a service with no topics says so" do
    empty = users(:amber).services.create!(name: "Empty")
    sign_in(users(:amber))

    get services_path

    assert_match "No topics yet", response.body
    assert_match empty.name, response.body
  end

  test "adding a service from the inline form" do
    sign_in(users(:amber))

    assert_difference -> { Service.count }, 1 do
      post services_path, params: { service: { name: "Hardware" } }
    end

    assert_redirected_to services_path
    assert_equal "Added Hardware.", flash[:notice]
  end

  test "a duplicate service name comes back as an alert, not a crash" do
    sign_in(users(:amber))

    assert_no_difference -> { Service.count } do
      post services_path, params: { service: { name: services(:website).name } }
    end

    assert_redirected_to services_path
    assert_match(/already one of your services/i, flash[:alert])
  end

  test "adding a topic under a service from its inline form" do
    sign_in(users(:amber))

    assert_difference -> { services(:website).topics.count }, 1 do
      post topics_path, params: { topic: { name: "Performance", service_id: services(:website).id } }
    end

    assert_redirected_to services_path
  end

  test "a service still in use can't be deleted" do
    sign_in(users(:amber))

    assert_no_difference -> { Service.count } do
      delete service_path(services(:website))
    end

    assert_redirected_to services_path
    assert flash[:alert].present?
  end

  test "an unused service can be deleted" do
    unused = users(:amber).services.create!(name: "Unused")
    sign_in(users(:amber))

    assert_difference -> { Service.count }, -1 do
      delete service_path(unused)
    end

    assert_redirected_to services_path
  end
end
