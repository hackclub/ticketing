# Everything that has happened to a ticket, in order: what people said to each
# other, the private notes alongside it, and every status change. Anything can
# carry files.
class TicketEvent < ApplicationRecord
  belongs_to :ticket
  belongs_to :author, class_name: "User"

  has_many_attached :files

  # The disk behind this is finite and shared, so one message can't be a
  # dumping ground.
  MAX_FILE_SIZE = 25.megabytes
  MAX_FILES = 10

  # What's safe to show in the page itself. Anything else — SVG included,
  # since it can carry script — is a download.
  PREVIEWABLE = %w[image/png image/jpeg image/gif image/webp].freeze

  # comment: both sides see it. internal_note: only whoever the ticket is for.
  # status_change: written by the app when a status moves.
  enum :kind, { comment: 0, internal_note: 1, status_change: 2 }, default: :comment

  # A status change is worth recording with nothing said; anything else needs
  # words or a file, or there's nothing there.
  validate :has_something_to_say
  validate :files_are_a_sensible_size

  scope :oldest_first, -> { order(:created_at, :id) }
  scope :for_requester, -> { where.not(kind: :internal_note) }

  after_create_commit :notify

  def visible_to?(user)
    internal_note? ? ticket.managed_by?(user) : ticket.visible_to?(user)
  end

  # A status change reads as a sentence rather than a message.
  def headline
    return unless status_change?

    from = from_status.present? ? Ticket.status_label(Ticket.statuses.key(from_status)) : nil
    to = Ticket.status_label(Ticket.statuses.key(to_status))
    from ? "moved this from #{from.downcase} to #{to.downcase}" : "set this to #{to.downcase}"
  end

  def previewable?(file)
    PREVIEWABLE.include?(file.content_type)
  end

  private

  def files_are_a_sensible_size
    return unless files.attached?

    errors.add(:files, "can't be more than #{MAX_FILES} at a time") if files.size > MAX_FILES

    too_big = files.reject { |file| file.byte_size <= MAX_FILE_SIZE }
    return if too_big.empty?

    errors.add(:files, "must each be under #{ActiveSupport::NumberHelper.number_to_human_size(MAX_FILE_SIZE)} " \
                       "(#{too_big.map { |file| file.filename }.join(', ')})")
  end

  def has_something_to_say
    return if status_change? || body.present? || files.attached?

    errors.add(:body, "can't be blank")
  end

  # A comment is a message to the other side, so it goes out like one. Notes
  # and status changes don't — status changes have their own notification.
  def notify
    return unless comment?

    TicketMailer.commented(self).deliver_later
    SlackNotificationJob.perform_later(ticket_id, "commented", id)
  end
end
