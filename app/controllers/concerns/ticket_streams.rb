# Anything that moves a ticket up or down the queue has to re-render the
# dashboard as well as the bit of the page that changed. Turbo drops any
# stream whose target isn't on the current page, so both can always be sent.
module TicketStreams
  extend ActiveSupport::Concern

  private

  def queue_stream
    turbo_stream.replace(
      "queue",
      partial: "dashboard/queue",
      locals: { tickets: Ticket.owned_by(current_user).needs_attention.ordered_for_admin.includes(:user, :service, :topic, :blockers) }
    )
  end

  # The count in the nav, which the favicon and tab title follow.
  def queue_badge_stream
    turbo_stream.replace("queue_badge", partial: "layouts/queue_badge")
  end

  # The deadline and blocked badges sit in the page header, away from the box
  # that edits them, so both move together.
  def scheduling_streams(ticket)
    [
      turbo_stream.replace(helpers.dom_id(ticket, :badges), partial: "tickets/badges", locals: { ticket: ticket }),
      turbo_stream.replace(helpers.dom_id(ticket, :scheduling), partial: "tickets/scheduling", locals: { ticket: ticket }),
      queue_stream
    ]
  end
end
