require "test_helper"

class TicketTest < ActiveSupport::TestCase
  def valid_attributes
    {
      user: users(:requester),
      service: services(:website),
      topic: topics(:bug),
      title: "Something broke",
      message: "Details here."
    }
  end

  test "valid with required attributes" do
    assert Ticket.new(valid_attributes).valid?
  end

  test "invalid when topic does not belong to the selected service" do
    ticket = Ticket.new(valid_attributes.merge(topic: topics(:access_request)))

    refute ticket.valid?
    assert_includes ticket.errors[:topic], "must belong to the selected service"
  end

  test "invalid with a non-http(s) url" do
    ticket = Ticket.new(valid_attributes.merge(url: "not a url"))

    refute ticket.valid?
    assert ticket.errors[:url].present?
  end

  test "valid with a blank url" do
    ticket = Ticket.new(valid_attributes.merge(url: ""))

    assert ticket.valid?
  end

  test "defaults to low priority and open status" do
    ticket = Ticket.create!(valid_attributes)

    assert ticket.low?
    assert ticket.open?
  end

  test "the database default matches the model default" do
    ticket = Ticket.create!(valid_attributes)

    assert_equal Ticket.columns_hash["priority"].default.to_i, Ticket.priorities[ticket.priority]
  end

  test "wont do is a closed state, so it drops off the queue" do
    ticket = Ticket.create!(valid_attributes)
    assert_includes Ticket.needs_attention, ticket

    ticket.update!(status: :wont_do)

    refute_includes Ticket.needs_attention, ticket
    assert_includes Ticket.needs_attention, Ticket.create!(valid_attributes)
  end

  test "every status reads as a sentence" do
    ticket = Ticket.new(valid_attributes)

    Ticket.statuses.each_key do |status|
      ticket.status = status
      assert ticket.status_sentence.present?
      refute_match(/_/, ticket.status_sentence, "#{status} still reads like an enum key")
    end

    ticket.status = :wont_do
    assert_equal "closed — won't do", ticket.status_sentence
    assert_equal "Won't do", ticket.status_label
  end

  test "every status has a label that isn't just the enum key" do
    Ticket.statuses.each_key do |status|
      label = Ticket.status_label(status)
      assert label.present?
      refute_match(/_/, label, "#{status} has no proper label")
    end

    # humanize would give "Wont do" — the apostrophe is why labels are mapped.
    assert_equal "Won't do", Ticket.status_label(:wont_do)
    assert_includes Ticket.status_options, [ "Won't do", "wont_do" ]
  end

  test "closing as wont do still notifies the requester" do
    ticket = Ticket.create!(valid_attributes)

    assert_enqueued_emails 1 do
      assert_enqueued_with job: SlackNotificationJob, args: [ ticket.id, "status_changed" ] do
        ticket.update!(status: :wont_do)
      end
    end
  end

  test "creating a ticket notifies by email and Slack" do
    assert_enqueued_emails 1 do
      assert_enqueued_with job: SlackNotificationJob do
        Ticket.create!(valid_attributes)
      end
    end
  end

  test "changing status notifies the requester by email and Slack" do
    ticket = Ticket.create!(valid_attributes)

    assert_enqueued_emails 1 do
      assert_enqueued_with job: SlackNotificationJob, args: [ ticket.id, "status_changed" ] do
        ticket.update!(status: :done)
      end
    end
  end

  test "editing something other than status does not notify" do
    ticket = Ticket.create!(valid_attributes)

    assert_no_enqueued_emails do
      ticket.update!(title: "A different title")
    end
  end

  # --- deadlines ---------------------------------------------------------

  test "a passed deadline on an unfinished ticket is overdue" do
    ticket = Ticket.create!(valid_attributes.merge(due_at: 2.days.ago))

    assert ticket.overdue?
    refute ticket.due_soon?
    assert_match(/overdue/, ticket.due_label)
  end

  test "a deadline inside the window is due soon" do
    ticket = Ticket.create!(valid_attributes.merge(due_at: 1.day.from_now))

    assert ticket.due_soon?
    refute ticket.overdue?
    assert_match(/\Adue in /, ticket.due_label)
  end

  test "a distant deadline is neither" do
    ticket = Ticket.create!(valid_attributes.merge(due_at: 3.weeks.from_now))

    refute ticket.due_soon?
    refute ticket.overdue?
  end

  test "a finished ticket is never overdue, and stops being nagged at" do
    ticket = Ticket.create!(valid_attributes.merge(due_at: 2.days.ago, status: :done))

    refute ticket.overdue?
    assert_match(/\Awas due /, ticket.due_label)
  end

  test "no deadline, no label" do
    assert_nil Ticket.new(valid_attributes).due_label
    assert_nil Ticket.new(valid_attributes).due_on
  end

  test "a deadline reads with its zone attached" do
    ticket = Ticket.create!(valid_attributes.merge(due_at: Time.utc(2026, 10, 1, 17, 0)))

    assert_match(/1 Oct 2026/, ticket.due_on)
    assert_match(/#{Time.zone.now.strftime('%Z')}/, ticket.due_on)
  end

  test "an imminent deadline outranks priority in the queue" do
    soon = Ticket.create!(valid_attributes.merge(title: "Due tomorrow", priority: :low, due_at: 1.day.from_now))
    urgent = Ticket.create!(valid_attributes.merge(title: "No deadline", priority: :urgent))

    queue = Ticket.needs_attention.ordered_for_admin.to_a

    assert_operator queue.index(soon), :<, queue.index(urgent)
  end

  test "the earlier of two deadlines comes first" do
    later = Ticket.create!(valid_attributes.merge(title: "Later", due_at: 2.days.from_now))
    sooner = Ticket.create!(valid_attributes.merge(title: "Sooner", due_at: 1.hour.from_now))

    queue = Ticket.needs_attention.ordered_for_admin.to_a

    assert_operator queue.index(sooner), :<, queue.index(later)
  end

  # --- blocking ----------------------------------------------------------

  test "a ticket is blocked only while its blocker is unfinished" do
    blocked = Ticket.create!(valid_attributes.merge(title: "Waiting"))
    blocker = Ticket.create!(valid_attributes.merge(title: "In the way"))
    blocked.blocked_links.create!(blocker_ticket: blocker)

    assert blocked.reload.blocked?

    blocker.update!(status: :done)

    refute blocked.reload.blocked?
  end

  test "a won't-do blocker unblocks too — it is never getting done" do
    blocked = Ticket.create!(valid_attributes.merge(title: "Waiting"))
    blocker = Ticket.create!(valid_attributes.merge(title: "In the way"))
    blocked.blocked_links.create!(blocker_ticket: blocker)
    blocker.update!(status: :wont_do)

    refute blocked.reload.blocked?
  end

  test "a blocked ticket sinks below one you can actually start" do
    blocked = Ticket.create!(valid_attributes.merge(title: "Blocked", priority: :urgent))
    startable = Ticket.create!(valid_attributes.merge(title: "Startable", priority: :low))
    blocked.blocked_links.create!(blocker_ticket: Ticket.create!(valid_attributes.merge(title: "Blocker")))

    queue = Ticket.needs_attention.ordered_for_admin.to_a

    assert_operator queue.index(startable), :<, queue.index(blocked)
  end

  test "finishing the blocker floats a ticket back up the queue" do
    blocked = Ticket.create!(valid_attributes.merge(title: "Blocked", priority: :urgent))
    startable = Ticket.create!(valid_attributes.merge(title: "Startable", priority: :low))
    blocker = Ticket.create!(valid_attributes.merge(title: "Blocker"))
    blocked.blocked_links.create!(blocker_ticket: blocker)

    blocker.update!(status: :done)
    queue = Ticket.needs_attention.ordered_for_admin.to_a

    assert_operator queue.index(blocked), :<, queue.index(startable)
  end

  test "candidates to wait on exclude the ticket itself and its current blockers" do
    ticket = Ticket.create!(valid_attributes.merge(title: "Mine"))
    blocker = Ticket.create!(valid_attributes.merge(title: "Already linked"))
    finished = Ticket.create!(valid_attributes.merge(title: "Finished", status: :done))
    ticket.blocked_links.create!(blocker_ticket: blocker)

    candidates = ticket.reload.blocker_candidates

    refute_includes candidates, ticket
    refute_includes candidates, blocker
    refute_includes candidates, finished
    assert_includes candidates, tickets(:website_bug)
  end

  test "a reference is short enough for a Slack option label" do
    ticket = Ticket.create!(valid_attributes.merge(title: "A " * 100))

    assert_operator ticket.reference.length, :<=, 75
  end

  # --- who a ticket is for ------------------------------------------------

  test "a ticket belongs to whoever owns the service it was filed under" do
    owner = another_owner
    service = owner.services.first

    ticket = Ticket.create!(valid_attributes.merge(service: service, topic: service.topics.first))

    assert_equal owner, ticket.owner
  end

  test "moving a ticket to another service moves who it's for" do
    owner = another_owner
    ticket = Ticket.create!(valid_attributes)
    assert_equal users(:amber), ticket.owner

    ticket.update!(service: owner.services.first, topic: owner.services.first.topics.first)

    assert_equal owner, ticket.reload.owner
  end

  test "only the person it's for — or an admin — manages a ticket" do
    owner = another_owner
    ticket = ticket_for(owner, requester: users(:requester))

    assert ticket.managed_by?(owner)
    assert ticket.managed_by?(users(:amber))
    refute ticket.managed_by?(users(:requester))
    refute ticket.managed_by?(nil)
  end

  test "the person who filed it can read it without managing it" do
    owner = another_owner
    ticket = ticket_for(owner, requester: users(:requester))

    assert ticket.visible_to?(users(:requester))
    refute ticket.managed_by?(users(:requester))
  end

  test "somebody with nothing to do with a ticket can't see it" do
    owner = another_owner
    ticket = ticket_for(owner)
    stranger = User.create!(sub: "sub_stranger", email: "stranger@example.com", name: "Stranger")

    refute ticket.visible_to?(stranger)
  end

  test "each queue is ordered on its own" do
    owner = another_owner
    mine = Ticket.create!(valid_attributes)
    theirs = ticket_for(owner)

    assert_includes Ticket.owned_by(users(:amber)).needs_attention, mine
    refute_includes Ticket.owned_by(users(:amber)).needs_attention, theirs
    assert_includes Ticket.owned_by(owner).needs_attention, theirs
  end

  test "blockers can only come from the same queue" do
    owner = another_owner
    theirs = ticket_for(owner)
    mine = Ticket.create!(valid_attributes)

    refute_includes theirs.blocker_candidates, mine
    assert_includes mine.blocker_candidates, tickets(:website_bug)
  end

  test "the new ticket is emailed to whoever it is for" do
    owner = another_owner

    perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
      ticket_for(owner, requester: users(:requester))
    end

    assert_equal [ owner.email ], ActionMailer::Base.deliveries.last.to
  end
end
