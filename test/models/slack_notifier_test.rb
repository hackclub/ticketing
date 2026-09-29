require "test_helper"

# The Block Kit templates are only exercised in production otherwise — a typo
# in one of them would go unnoticed until Slack refused the view.
class SlackNotifierTest < ActiveSupport::TestCase
  def blocked_and_late
    ticket = tickets(:website_bug)
    blocker = users(:amber).tickets.create!(
      title: "The thing it waits on", message: "…", service: services(:slack), topic: topics(:access_request)
    )
    ticket.update!(due_at: 2.days.ago)
    ticket.blocked_links.create!(blocker_ticket: blocker)
    ticket
  end

  test "the Home tab renders a blocked, overdue ticket" do
    blocked_and_late
    client = FakeSlackClient.new

    with_slack_client(client) do
      SlackNotifier.publish_home(users(:amber).slack_id)
    end

    rendered = ApplicationController.render(
      template: "slack/home/show", formats: [ :slack_message ],
      locals: { user: users(:amber), tickets: Ticket.needs_attention.ordered_for_admin, slack_user_id: users(:amber).slack_id }
    )

    assert_match "overdue", rendered
    assert_match "blocked", rendered
  end

  test "the new-ticket DM mentions the deadline" do
    rendered = ApplicationController.render(
      template: "slack/notifications/ticket_created", formats: [ :slack_message ],
      locals: { ticket: blocked_and_late }
    )

    assert_match "due", rendered
  end

  test "the status-change DM mentions the deadline" do
    rendered = ApplicationController.render(
      template: "slack/notifications/ticket_status_changed", formats: [ :slack_message ],
      locals: { ticket: blocked_and_late }
    )

    assert_match "due", rendered
  end

  test "the update modal shows what a ticket is waiting on" do
    ticket = blocked_and_late

    rendered = ApplicationController.render(
      template: "slack/tickets/update", formats: [ :slack_modal ],
      locals: { ticket: ticket, status: "in_progress" }
    )

    assert_match "Waiting on ##{ticket.blockers.first.id}", rendered
    assert_match "Clear it", rendered
  end

  test "the new-ticket modal offers a deadline picker" do
    rendered = ApplicationController.render(
      template: "slack/tickets/new", formats: [ :slack_modal ],
      locals: { services: Service.active.includes(:topics), initial_message: nil, initial_url: nil }
    )

    assert_match "datetimepicker", rendered
  end

  test "a new ticket is DM'd to whoever it's for, not to every admin" do
    owner = another_owner
    owner.update!(slack_id: "U000BO")
    client = FakeSlackClient.new

    with_slack_enabled do
      with_slack_client(client) do
        SlackNotifier.ticket_created(ticket_for(owner, requester: users(:requester)))
      end
    end

    assert_equal [ "U000BO" ], client.calls[:chat_postMessage].map { |call| call[:channel] }
  end

  test "the Home tab shows an enabled person their own queue" do
    owner = another_owner
    owner.update!(slack_id: "U000BO")
    ticket_for(owner, requester: users(:requester), title: "Filed to Bo")

    rendered = ApplicationController.render(
      template: "slack/home/show", formats: [ :slack_message ],
      locals: { user: owner, tickets: Ticket.owned_by(owner).needs_attention, slack_user_id: owner.slack_id }
    )

    assert_match "Filed to Bo", rendered
    assert_match "Everything on your plate", rendered
    assert_no_match(/#{tickets(:website_bug).title}/, rendered)
  end

  test "the new-ticket modal says whose services are whose once there are two" do
    another_owner

    rendered = ApplicationController.render(
      template: "slack/tickets/new", formats: [ :slack_modal ],
      locals: { services: Service.fileable.fallback_last, initial_message: nil, initial_url: nil }
    )

    assert_match "Bo Owner · Other", rendered
    assert_match "#{users(:amber).display_name} · Website", rendered
  end
end
