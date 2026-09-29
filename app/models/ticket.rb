class Ticket < ApplicationRecord
  # user is whoever filed it; owner is whoever has to do something about it.
  belongs_to :user
  belongs_to :owner, class_name: "User"
  belongs_to :service
  belongs_to :topic

  has_many :events, class_name: "TicketEvent", dependent: :destroy

  # "This ticket is waiting on those ones", and the reverse.
  has_many :blocked_links, class_name: "TicketBlock", foreign_key: :blocked_ticket_id, dependent: :destroy
  has_many :blockers, through: :blocked_links, source: :blocker_ticket
  has_many :blocking_links, class_name: "TicketBlock", foreign_key: :blocker_ticket_id, dependent: :destroy
  has_many :blocking, through: :blocking_links, source: :blocked_ticket

  enum :priority, { low: 0, medium: 1, high: 2, urgent: 3 }, default: :low
  enum :status, { open: 0, in_progress: 1, done: 2, wont_do: 3 }, default: :open

  # How close a deadline has to be before it starts outranking priority in
  # the queue, and before the badge turns amber.
  DUE_SOON = 3.days

  # humanize can't produce "Won't do", and "your ticket is now won't do"
  # doesn't parse — so labels and sentence forms both live here rather than
  # being reinvented by each of the web, Slack and MCP surfaces.
  STATUS_LABELS = {
    "open" => "Open",
    "in_progress" => "In progress",
    "done" => "Done",
    "wont_do" => "Won't do"
  }.freeze

  STATUS_SENTENCES = {
    "open" => "open again",
    "in_progress" => "in progress",
    "done" => "done",
    "wont_do" => "closed — won't do"
  }.freeze

  def self.status_label(status)
    STATUS_LABELS.fetch(status.to_s, status.to_s.humanize)
  end

  # [label, value] pairs for every select in the app.
  def self.status_options
    statuses.keys.map { |status| [ status_label(status), status ] }
  end

  def status_label
    self.class.status_label(status)
  end

  def status_sentence
    STATUS_SENTENCES.fetch(status, status.humanize.downcase)
  end

  # The service decides who the ticket is for, so the two can never disagree
  # and no form has to ask twice.
  before_validation :inherit_owner_from_service

  validates :title, presence: true
  validates :message, presence: true
  validate :topic_belongs_to_service
  validate :url_must_be_http_or_https

  scope :needs_attention, -> { where(status: [ :open, :in_progress ]) }
  scope :owned_by, ->(user) { where(owner_id: user.id) }
  scope :closed, -> { where(status: [ :done, :wont_do ]) }

  # Whether anything unfinished is standing in this ticket's way, as SQL, so
  # the queue can sort on it without loading every ticket's blockers.
  OUTSTANDING_BLOCKERS = <<~SQL.squish.freeze
    EXISTS (
      SELECT 1 FROM ticket_blocks
      JOIN tickets AS blockers ON blockers.id = ticket_blocks.blocker_ticket_id
      WHERE ticket_blocks.blocked_ticket_id = tickets.id
        AND blockers.status IN (#{statuses[:open]}, #{statuses[:in_progress]})
    )
  SQL

  scope :ordered_for_admin, -> { joins(:user).order(Arel.sql(admin_order_sql)) }

  # A ticket you can't start yet is noise at the top of a queue, so blocked
  # ones sink; a deadline that's nearly here outranks a vague "urgent", so
  # those rise; everything else keeps the old VIP → priority → age order.
  def self.admin_order_sql
    sanitize_sql_array([
      "(#{OUTSTANDING_BLOCKERS}) ASC, " \
      "(tickets.due_at IS NOT NULL AND tickets.due_at <= ?) DESC, " \
      "users.priority_boost DESC, tickets.priority DESC, " \
      "tickets.due_at ASC NULLS LAST, tickets.created_at ASC",
      DUE_SOON.from_now
    ])
  end

  # Notifications and timeline entries live here rather than in the
  # controllers, so a ticket filed or changed from Slack behaves exactly like
  # one from the web.
  after_create_commit :notify_created
  after_update_commit :notify_status_changed, if: :saved_change_to_status?
  after_update_commit :record_status_change, if: :saved_change_to_status?

  # --- deadlines ---------------------------------------------------------

  def needs_attention?
    open? || in_progress?
  end

  def overdue?
    due_at.present? && needs_attention? && due_at.past?
  end

  def due_soon?
    due_at.present? && needs_attention? && !due_at.past? && due_at <= DUE_SOON.from_now
  end

  # "2 days overdue" / "due in about 5 hours" — one phrasing for the web,
  # Slack and MCP. Finished tickets don't get nagged at.
  def due_label
    return if due_at.blank?

    return "was due #{due_on}" unless needs_attention?

    distance = ActionController::Base.helpers.distance_of_time_in_words(Time.current, due_at)
    due_at.past? ? "#{distance} overdue" : "due in #{distance}"
  end

  # Deadlines are only meaningful with their zone attached — the app's zone
  # isn't necessarily the reader's.
  def due_on
    due_at&.in_time_zone&.strftime("%-d %b %Y at %-l:%M %p %Z")
  end

  # --- blocking ----------------------------------------------------------

  # Filtered in Ruby so a preloaded :blockers association answers this
  # without a query per ticket when a whole queue is being rendered.
  def outstanding_blockers
    blockers.select(&:needs_attention?)
  end

  def blocked?
    outstanding_blockers.any?
  end

  # Walks the whole chain, not just the direct blockers: if x waits on y and
  # y waits on f, then x is waiting on f too.
  def blocked_by_transitively?(other)
    seen = Set.new([ id ])
    pending = blockers.to_a

    while (ticket = pending.shift)
      return true if ticket.id == other.id
      next unless seen.add?(ticket.id)

      pending.concat(ticket.blockers.to_a)
    end

    false
  end

  # Everything still outstanding that could sensibly be waited on. Cycles
  # aren't filtered out here — TicketBlock rejects those with a message that
  # explains which chain the link would close.
  def blocker_candidates
    return Ticket.none if owner.nil?

    Ticket.owned_by(owner).needs_attention.where.not(id: [ id, *blockers.ids ].compact).order(created_at: :desc)
  end

  # A ticket is a conversation between whoever filed it and whoever has to do
  # something about it; this is the person on the other end from whoever just
  # spoke. An admin speaking on someone else's ticket answers the requester.
  def other_party(speaker)
    speaker.id == user_id ? owner : user
  end

  # Whose job it is to deal with this, versus who is merely allowed to read it.
  def managed_by?(user)
    user.present? && (user.admin? || owner_id == user.id)
  end

  def visible_to?(user)
    user.present? && (managed_by?(user) || user_id == user.id)
  end

  # Short enough for an error message or a Slack line.
  def reference
    "##{id} #{title.to_s.truncate(60)}".strip
  end

  private

  def inherit_owner_from_service
    self.owner_id = service.owner_id if service.present?
  end

  def notify_created
    TicketMailer.created(self).deliver_later
    SlackNotificationJob.perform_later(id, "created")
  end

  def notify_status_changed
    TicketMailer.status_changed(self).deliver_later
    SlackNotificationJob.perform_later(id, "status_changed")
  end

  # Written here rather than at each call site so a status changed from the
  # web, Slack or the MCP tools all leave the same mark on the timeline.
  def record_status_change(*)
    before, after = saved_change_to_status
    events.create!(
      kind: :status_change, author: Current.user || owner, body: status_note.presence,
      from_status: self.class.statuses[before], to_status: self.class.statuses[after]
    )
  end

  def topic_belongs_to_service
    return if topic.blank? || service.blank?

    errors.add(:topic, "must belong to the selected service") if topic.service_id != service_id
  end

  def url_must_be_http_or_https
    return if url.blank?

    uri = URI.parse(url)
    errors.add(:url, "must be a valid http(s) URL") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:url, "must be a valid URL")
  end
end
