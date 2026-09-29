class Service < ApplicationRecord
  # Whoever owns the service is who its tickets are for, so nothing else has
  # to ask who a ticket is going to.
  belongs_to :owner, class_name: "User"

  has_many :topics, dependent: :restrict_with_error
  has_many :tickets, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :owner_id, message: "is already one of your services" }

  scope :active, -> { where(active: true) }

  # Filing needs a live service belonging to someone who is still taking
  # tickets — switching a person off closes their services with them.
  scope :fileable, -> { active.where(owner_id: User.ticket_owners).includes(:topics, :owner) }

  # The catch-all for a request that doesn't fit anything else. It's a
  # fallback rather than a project, so it belongs at the bottom of every
  # picker however the alphabet happens to fall.
  FALLBACK_NAME = "Other".freeze

  scope :fallback_last, -> { order(Arel.sql(fallback_last_sql)) }

  def self.fallback_last_sql
    sanitize_sql_array([ "CASE WHEN services.name = ? THEN 1 ELSE 0 END, services.name", FALLBACK_NAME ])
  end

  def fallback?
    name == FALLBACK_NAME
  end

  # Somewhere to file a request that doesn't fit anything this person has set
  # up — and, when they've only just been enabled, the thing that makes them
  # fileable at all.
  def self.fallback_for(owner)
    service = owner.services.find_or_create_by!(name: FALLBACK_NAME)
    service.topics.find_or_create_by!(name: "General Request")
    service
  end

  # Grouped for a picker: "Amber" → her services, and so on. One list, so no
  # surface needs a separate "who is this for" field.
  # Takes anything enumerable — a relation or a plain list — so callers can
  # preload as they see fit.
  def self.grouped_by_owner(services)
    services.group_by(&:owner).sort_by { |owner, _| owner.display_name.downcase }
  end
end
