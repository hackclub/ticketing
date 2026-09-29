module Slack
  class InteractionsController < BaseController
    MODAL_CALLBACK = "create_ticket".freeze

    def create
      payload = JSON.parse(params.require(:payload))

      case payload["type"]
      when "shortcut"        then open_modal(payload)
      when "message_action"  then open_modal(payload, message: payload["message"], channel: payload.dig("channel", "id"))
      when "view_submission" then handle_submission(payload)
      when "block_actions"   then handle_block_action(payload)
      else head :ok
      end
    end

    private

    def handle_submission(payload)
      case payload.dig("view", "callback_id")
      when "update_ticket" then submit_status(payload)
      when "comment_ticket" then submit_comment(payload)
      else submit_ticket(payload)
      end
    end

    def open_modal(payload, message: nil, channel: nil)
      view = render_to_string(
        template: "slack/tickets/new",
        formats: [ :slack_modal ],
        locals: {
          services: Service.fileable.fallback_last,
          initial_message: SlackText.to_markdown(message&.dig("text"), client: SlackNotifier.reader).presence,
          initial_url: message && permalink_for(channel, message["ts"])
        }
      )

      slack_client.views_open(trigger_id: payload["trigger_id"], view: JSON.parse(view))
      head :ok
    end

    def submit_ticket(payload)
      values = payload.dig("view", "state", "values")
      user = User.find_or_create_from_slack(payload.dig("user", "id"), slack_client)
      Current.user = user
      service_id, topic_id = selected(values, "topic").to_s.split(":")

      ticket = user.tickets.new(
        title: input(values, "title"),
        service_id: service_id,
        topic_id: topic_id,
        priority: selected(values, "priority"),
        url: input(values, "url"),
        message: input(values, "message"),
        due_at: picked_time(values, "due")
      )

      if ticket.save
        SlackHomeJob.perform_later(user.slack_id)
        render json: {
          response_action: "update",
          view: JSON.parse(render_to_string(template: "slack/tickets/created", formats: [ :slack_modal ], locals: { ticket: ticket }))
        }
      else
        render json: { response_action: "errors", errors: modal_errors(ticket) }
      end
    end

    def handle_block_action(payload)
      action = payload["actions"].to_a.first
      slack_user_id = payload.dig("user", "id")

      case action&.dig("action_id")
      when "open_new_ticket"
        open_modal(payload)
      when "set_status"
        open_status_modal(payload, action, slack_user_id)
        head :ok
      when "comment_ticket"
        open_comment_modal(payload, action["value"], slack_user_id)
        head :ok
      else
        head :ok
      end
    end

    # Picking a status opens a modal rather than applying straight away, so
    # there's somewhere to write the note that goes out with it.
    def open_status_modal(payload, action, slack_user_id)
      user = User.find_or_create_from_slack(slack_user_id, slack_client)

      ticket_id, status = action.dig("selected_option", "value").to_s.split(":")
      ticket = Ticket.find_by(id: ticket_id)
      return if ticket.nil? || !ticket.managed_by?(user)

      view = render_to_string(
        template: "slack/tickets/update",
        formats: [ :slack_modal ],
        locals: { ticket: ticket, status: status }
      )

      slack_client.views_open(trigger_id: payload["trigger_id"], view: JSON.parse(view))
    end

    # Reply straight from the DM, rather than going to the web to type a line.
    def open_comment_modal(payload, ticket_id, slack_user_id)
      user = User.find_or_create_from_slack(slack_user_id, slack_client)
      ticket = Ticket.find_by(id: ticket_id)
      return if ticket.nil? || !ticket.visible_to?(user)

      view = render_to_string(
        template: "slack/tickets/comment",
        formats: [ :slack_modal ],
        locals: { ticket: ticket, author: user }
      )

      slack_client.views_open(trigger_id: payload["trigger_id"], view: JSON.parse(view))
    end

    def submit_comment(payload)
      user = User.find_or_create_from_slack(payload.dig("user", "id"), slack_client)
      Current.user = user
      ticket = Ticket.find_by(id: payload.dig("view", "private_metadata"))
      body = input(payload.dig("view", "state", "values"), "body")

      if ticket&.visible_to?(user) && body.present?
        ticket.events.create(kind: :comment, body: body, author: user)
      end

      head :ok
    end

    def submit_status(payload)
      user = User.find_or_create_from_slack(payload.dig("user", "id"), slack_client)
      Current.user = user
      ticket_id, status = payload.dig("view", "private_metadata").to_s.split(":")
      ticket = Ticket.find_by(id: ticket_id)
      values = payload.dig("view", "state", "values")

      if ticket&.managed_by?(user) && Ticket.statuses.key?(status)
        ticket.update(status: status, status_note: input(values, "note"), **deadline_change(values, ticket))

        internal = input(values, "internal_note")
        ticket.events.create(kind: :internal_note, body: internal, author: user) if internal.present?

        blocker_id = selected(values, "blocker")
        ticket.blocked_links.create(blocker_ticket_id: blocker_id) if blocker_id.present?
      end

      SlackHomeJob.perform_later(user.slack_id)
      head :ok
    end

    def permalink_for(channel, message_ts)
      return if channel.blank? || message_ts.blank?

      slack_client.chat_getPermalink(channel: channel, message_ts: message_ts)["permalink"]
    rescue ::Slack::Web::Api::Errors::SlackError => e
      Rails.logger.warn("Could not fetch Slack permalink: #{e.message}")
      nil
    end

    # Modal errors are keyed by block_id, which we keep equal to the field name.
    def modal_errors(ticket)
      { "title" => :title, "message" => :message, "url" => :url, "topic" => :topic }
        .transform_values { |attribute| ticket.errors[attribute].to_sentence.presence }
        .compact
        .presence || { "title" => ticket.errors.full_messages.to_sentence }
    end

    # The modal can set a deadline or clear it; an untouched picker leaves it
    # alone, so the attribute is only included when something was said.
    def deadline_change(values, ticket)
      return { due_at: nil } if checked?(values, "clear_due")

      due = picked_time(values, "due")
      due && due != ticket.due_at ? { due_at: due } : {}
    end

    # A datetimepicker hands back a unix timestamp, or nothing when untouched.
    def picked_time(values, block_id)
      epoch = values.dig(block_id, block_id, "selected_date_time")

      Time.zone.at(epoch) if epoch.present?
    end

    def checked?(values, block_id)
      values.dig(block_id, block_id, "selected_options").present?
    end

    def input(values, block_id)
      values.dig(block_id, block_id, "value")
    end

    def selected(values, block_id)
      values.dig(block_id, block_id, "selected_option", "value")
    end
  end
end
