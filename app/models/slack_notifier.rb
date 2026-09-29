# Thin wrapper around the Slack Web API. Every call is a no-op when no bot
# token is configured, so development and tests don't need Slack set up.
class SlackNotifier
  class << self
    def enabled?
      ENV["SLACK_BOT_TOKEN"].present?
    end

    def client
      ::Slack::Web::Client.new(token: ENV.fetch("SLACK_BOT_TOKEN", nil))
    end

    # Read-only lookups (channel and user names) go through Amber's user token
    # when one is configured, because a bot can't see inside private channels
    # or DMs it isn't in. Never used for posting — that stays the bot.
    def reader
      token = ENV["SLACK_USER_TOKEN"].presence
      return client if token.nil?

      ::Slack::Web::Client.new(token: token)
    end

    def ticket_created(ticket)
      return if ticket.owner.slack_id.blank?

      dm(ticket.owner.slack_id, "New ticket: #{ticket.title}", "slack/notifications/ticket_created", ticket: ticket)
    end

    def ticket_status_changed(ticket)
      return if ticket.user.slack_id.blank?

      dm(ticket.user.slack_id,
         "Your ticket is now #{ticket.status_sentence}",
         "slack/notifications/ticket_status_changed",
         ticket: ticket)
    end

    # A comment goes to whoever is on the other side of the conversation.
    def ticket_commented(event)
      return if event.nil? || !event.comment?

      recipient = event.ticket.other_party(event.author)
      return if recipient.slack_id.blank?

      dm(recipient.slack_id,
         "#{event.author.display_name} added to \"#{event.ticket.title}\"",
         "slack/notifications/ticket_commented",
         event: event)
    end

    def publish_home(slack_user_id)
      user = User.find_by(slack_id: slack_user_id)
      tickets = home_tickets(user)

      blocks = render("slack/home/show", user: user, tickets: tickets, slack_user_id: slack_user_id)

      call { client.views_publish(user_id: slack_user_id, view: blocks.merge("type" => "home")) }
    end

    def ticket_url(ticket)
      Rails.application.routes.url_helpers.ticket_url(ticket, host: app_host, protocol: protocol)
    end

    def url_for_path(path)
      "#{protocol}://#{app_host}#{path}"
    end

    private

    def home_tickets(user)
      if user&.receives_tickets?
        Ticket.owned_by(user).needs_attention.ordered_for_admin
              .includes(:user, :service, :topic, :blockers).limit(40)
      elsif user
        user.tickets.order(created_at: :desc).includes(:service, :topic, :blockers).limit(40)
      else
        Ticket.none
      end
    end

    def dm(slack_user_id, text, template, **locals)
      blocks = render(template, **locals)
      call { client.chat_postMessage(channel: slack_user_id, text: text, blocks: blocks["blocks"]) }
    end

    def render(template, **locals)
      JSON.parse(ApplicationController.render(template: template, formats: [ :slack_message ], locals: locals))
    end

    # Slack being down or misconfigured must never take a ticket down with it.
    def call
      return unless enabled?

      yield
    rescue ::Slack::Web::Api::Errors::SlackError, Faraday::Error => e
      Rails.logger.error("Slack API call failed: #{e.class}: #{e.message}")
      nil
    end

    def app_host
      ENV.fetch("APP_HOST", "localhost:3000")
    end

    def protocol
      app_host.start_with?("localhost") ? "http" : "https"
    end
  end
end
