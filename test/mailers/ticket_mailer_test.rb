require "test_helper"

class TicketMailerTest < ActionMailer::TestCase
  test "created notifies admins" do
    mail = TicketMailer.created(tickets(:website_bug))

    assert_equal User.admin_emails, mail.to
    assert_match tickets(:website_bug).title, mail.subject
  end

  test "status_changed notifies the requester" do
    mail = TicketMailer.status_changed(tickets(:website_bug))

    assert_equal [ tickets(:website_bug).user.email ], mail.to
    assert_match "Your ticket", mail.subject
  end

  test "a ticket the requester closed is reported to its owner instead" do
    ticket = tickets(:website_bug)
    ticket.update_columns(status: Ticket.statuses[:wont_do])

    mail = TicketMailer.status_changed(ticket, ticket.owner)

    assert_equal [ users(:amber).email ], mail.to
    assert_equal %(Some Requester closed "#{ticket.title}" (won't do)), mail.subject
    assert_match "Some Requester closed their ticket (won't do)", mail.text_part.body.to_s
  end
end
