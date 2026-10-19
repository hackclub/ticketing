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

  # To the requester normally; to the owner when the requester closed it.
  def status_changed(ticket, recipient = ticket.user)
    @ticket = ticket
    @headline = ticket.status_headline(recipient)

    subject = if recipient.id == ticket.user_id
      "Your ticket \"#{ticket.title}\" is now #{ticket.status_sentence}"
    else
      "#{ticket.user.display_name} closed \"#{ticket.title}\" (#{ticket.status_label.downcase})"
    end

    mail to: recipient.email, subject: subject
  end
end
