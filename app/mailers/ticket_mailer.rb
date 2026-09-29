class TicketMailer < ApplicationMailer
  def created(ticket)
    @ticket = ticket

    mail to: ticket.owner.email, subject: "New ticket: #{ticket.title}"
  end

  def commented(event)
    @event = event
    @ticket = event.ticket
    @author = event.author

    mail to: event.ticket.other_party(event.author).email,
         subject: "#{@author.display_name} on \"#{@ticket.title}\""
  end

  def status_changed(ticket)
    @ticket = ticket

    mail to: ticket.user.email, subject: "Your ticket \"#{ticket.title}\" is now #{ticket.status_sentence}"
  end
end
