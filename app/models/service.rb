class Service < ApplicationRecord
  has_many :topics, dependent: :restrict_with_error
  has_many :tickets, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }

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
end
