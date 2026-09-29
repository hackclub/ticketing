class User < ApplicationRecord
  # Tickets they filed, and — for someone who runs a queue of their own —
  # the tickets filed to them and the services those are filed under.
  has_many :tickets, dependent: :destroy
  has_many :owned_tickets, class_name: "Ticket", foreign_key: :owner_id, dependent: :restrict_with_error,
           inverse_of: :owner
  has_many :services, foreign_key: :owner_id, dependent: :restrict_with_error, inverse_of: :owner
  has_many :oauth_tokens, dependent: :delete_all
  has_many :oauth_grants, dependent: :delete_all

  validates :sub, presence: true, uniqueness: true
  validates :email, presence: true

  scope :admins, -> { where(admin: true) }
  scope :ticket_owners, -> { where(receives_tickets: true) }
  scope :on_slack, -> { where.not(slack_id: [ nil, "" ]) }

  TOKEN_PREFIX = "tkt_".freeze

  # Turning this on is what "letting someone use the tracker" means: people
  # can file to them, they can file to themselves, and Slack and the MCP
  # tools start working against their queue. Nobody can be filed to without
  # at least one service, so they get the catch-all to start with.
  def start_receiving_tickets!
    transaction do
      update!(receives_tickets: true)
      Service.fallback_for(self)
    end
  end

  def stop_receiving_tickets!
    update!(receives_tickets: false)
  end

  def display_name
    name.presence || email
  end

  # Personal access token for the MCP endpoint. Only the digest is stored, so
  # the raw token is shown once at generation time and can't be recovered.
  def regenerate_api_token!
    raw = "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
    update!(api_token_digest: self.class.digest_api_token(raw))
    raw
  end

  def revoke_api_token!
    update!(api_token_digest: nil)
  end

  def api_token?
    api_token_digest.present?
  end

  def self.authenticate_api_token(raw)
    return if raw.blank?

    find_by(api_token_digest: digest_api_token(raw))
  end

  def self.digest_api_token(raw)
    OpenSSL::Digest::SHA256.hexdigest(raw)
  end

  def self.admin_emails
    ENV.fetch("ADMIN_EMAILS", "amber@hackclub.com").split(",").map { |e| e.strip.downcase }
  end

  def self.admin_slack_ids
    ENV.fetch("ADMIN_SLACK_IDS", "U054VC2KM9P").split(",").map(&:strip).reject(&:blank?)
  end

  # Builds/updates a User from the omniauth.auth hash set by either the
  # real :hackclub (OpenID Connect) strategy or the development-only
  # :developer fallback strategy.
  def self.from_omniauth(auth)
    slack_id = extract_slack_id(auth)

    # Slack ID is the identity, so someone who first showed up through the
    # Slack app keeps their tickets when they later sign in here.
    user = (slack_id.present? && find_by(slack_id: slack_id)) || find_or_initialize_by(sub: auth.uid)
    user.sub = auth.uid
    user.email = auth.info.email
    user.name = auth.info.name
    user.slack_id = slack_id.presence || user.slack_id
    apply_defaults(user)
    user.save!
    user
  end

  # Someone interacting with the Slack app who may never have signed in here.
  # Matched on Slack ID only — never on email.
  def self.find_or_create_from_slack(slack_user_id, client)
    existing = find_by(slack_id: slack_user_id)
    return existing if existing

    profile = client.users_info(user: slack_user_id).user

    user = new(
      sub: "slack:#{slack_user_id}",
      slack_id: slack_user_id,
      name: profile.profile.real_name.presence || profile.name,
      email: profile.profile.email.presence || "#{slack_user_id}@users.noreply.slack.com"
    )
    apply_defaults(user)
    user.save!
    user
  end

  def self.apply_defaults(user)
    user.priority_boost = user.email.to_s.end_with?("@hackclub.com") if user.new_record?
    user.admin = admin_emails.include?(user.email.to_s.downcase) ||
                 admin_slack_ids.include?(user.slack_id.to_s)
    # An admin runs the tracker by definition; nobody else is switched on
    # here, since that's Amber's call to make on the person's page.
    user.receives_tickets = true if user.admin?
  end
  private_class_method :apply_defaults

  def self.extract_slack_id(auth)
    auth.info["slack_id"] || auth.extra&.raw_info&.slack_id
  end
  private_class_method :extract_slack_id
end
