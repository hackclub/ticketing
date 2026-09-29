require "test_helper"

# Admin used to be whatever ADMIN_EMAILS said and nothing else. Now it can be
# granted in the app — which means the environment list has to stop taking it
# away again at the next sign-in.
class MakingAdminsTest < ActionDispatch::IntegrationTest
  def sign_in(user)
    get "/auth/developer/callback", params: { name: user.name, email: user.email }
  end

  test "an admin can make somebody else one" do
    sign_in(users(:amber))
    person = users(:requester)

    patch admin_user_path(person), params: { user: { admin: "1" } }

    assert person.reload.admin?
    # An admin runs the tracker, so they get a queue with it.
    assert person.receives_tickets?
    assert_equal [ "Other" ], person.services.map(&:name)
  end

  test "and can take it away again" do
    person = users(:requester)
    person.make_admin!
    sign_in(users(:amber))

    patch admin_user_path(person), params: { user: { admin: "0" } }

    refute person.reload.admin?
    # They keep the queue they were given — only the admin part goes.
    assert person.receives_tickets?
  end

  test "being made an admin survives signing in again" do
    person = users(:requester)
    person.make_admin!

    sign_in(person)

    assert person.reload.admin?
  end

  test "you can't change your own" do
    sign_in(users(:amber))

    patch admin_user_path(users(:amber)), params: { user: { admin: "0" } }

    assert users(:amber).reload.admin?
    assert_match(/your own/, flash[:alert])
  end

  test "an admin from the environment can't be demoted in the app" do
    sign_in(users(:amber))
    configured = User.create!(sub: "env@hackclub.com", email: "env@hackclub.com", name: "Env Admin", admin: true)

    with_env("ADMIN_EMAILS" => "env@hackclub.com") do
      patch admin_user_path(configured), params: { user: { admin: "0" } }
    end

    assert configured.reload.admin?
    assert_match(/ADMIN_EMAILS/, flash[:alert])
  end

  test "nobody else can hand out admin" do
    sign_in(users(:requester))

    patch admin_user_path(users(:requester)), params: { user: { admin: "1" } }

    assert_redirected_to root_path
    refute users(:requester).reload.admin?
  end

  private

  def with_env(values)
    original = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end
end
