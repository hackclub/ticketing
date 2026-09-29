ENV["RAILS_ENV"] ||= "test"
ENV["SLACK_SIGNING_SECRET"] ||= "test-signing-secret"
require_relative "../config/environment"
require "rails/test_help"

# Stands in for Slack::Web::Client, recording calls and returning the shapes
# the app actually reads back.
class FakeSlackClient
  attr_reader :calls

  def initialize(profile: nil)
    @calls = Hash.new { |hash, key| hash[key] = [] }
    @profile = profile || {
      name: "someone",
      profile: { real_name: "Some One", display_name: "amber", email: "someone@example.com" }
    }
  end

  def method_missing(name, **kwargs)
    @calls[name] << kwargs

    case name
    when :users_info then Hashie::Mash.new(user: @profile)
    when :conversations_info
      if kwargs[:channel].to_s.start_with?("D")
        Hashie::Mash.new(channel: { id: kwargs[:channel], is_im: true, user: "U054VC2KM9P" })
      else
        Hashie::Mash.new(channel: { id: kwargs[:channel], name: "hcb-grants" })
      end
    when :chat_getPermalink then { "permalink" => "https://hackclub.slack.com/archives/C1/p1700000000" }
    else { "ok" => true }
    end
  end

  def respond_to_missing?(_name, _include_private = false) = true
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include ActionMailer::TestHelper

    # Somebody else Amber has let in: their own queue, their own catch-all
    # service, and nothing to do with hers.
    def another_owner(name: "Bo Owner", email: "bo@example.com")
      # The :developer strategy uses the email as the uid, same as the
      # fixtures, so signing in as them finds this row rather than making
      # a second one.
      user = User.create!(sub: email, email: email, name: name)
      user.start_receiving_tickets!
      user
    end

    def ticket_for(owner, requester: nil, title: "Something for you", **attributes)
      service = owner.services.first
      Ticket.create!(
        user: requester || owner, service: service, topic: service.topics.first,
        title: title, message: "Details here.", **attributes
      )
    end

    # Slack calls no-op without a token, which is what dev and most tests
    # want — but not a test about who gets the message.
    def with_slack_enabled
      was = ENV["SLACK_BOT_TOKEN"]
      ENV["SLACK_BOT_TOKEN"] = "xoxb-test"
      yield
    ensure
      ENV["SLACK_BOT_TOKEN"] = was
    end

    # Minitest 6 dropped Object#stub, and this is the only seam we need.
    def with_slack_client(client = FakeSlackClient.new)
      original = SlackNotifier.method(:client)
      SlackNotifier.define_singleton_method(:client) { client }
      yield
    ensure
      SlackNotifier.define_singleton_method(:client, original)
    end
  end
end

module SlackRequestHelpers
  # Signs a request the way Slack does, so the controller's verification runs
  # for real in tests rather than being stubbed out.
  def slack_post(path, body, content_type: "application/x-www-form-urlencoded")
    timestamp = Time.now.to_i.to_s
    signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("SLACK_SIGNING_SECRET"), "v0:#{timestamp}:#{body}")

    post path, params: body, headers: {
      "CONTENT_TYPE" => content_type,
      "X-Slack-Request-Timestamp" => timestamp,
      "X-Slack-Signature" => signature
    }
  end

  def interaction_body(payload)
    URI.encode_www_form(payload: payload.to_json)
  end
end
