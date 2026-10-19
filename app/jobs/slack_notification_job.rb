class SlackNotificationJob < ApplicationJob
  queue_as :default

  def perform(ticket_id, kind, event_id = nil, recipient_id = nil)
    ticket = Ticket.find_by(id: ticket_id)
    return if ticket.nil?

    case kind
    when "created" then SlackNotifier.ticket_created(ticket)
    when "status_changed" then SlackNotifier.ticket_status_changed(ticket, User.find_by(id: recipient_id) || ticket.user)
    when "commented" then SlackNotifier.ticket_commented(TicketEvent.find_by(id: event_id))
    end
  end
end
