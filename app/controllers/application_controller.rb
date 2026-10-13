class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :start_request_timer
  before_action :require_login
  before_action :remember_who_is_acting

  helper_method :current_user, :admin?, :owner?, :manages?, :everyone?, :filed_by_me?, :queue_counts

  private

  # Turbo Stream responses don't redirect, so the flash has to be swapped in
  # directly rather than surviving to the next page load.
  def flash_stream(notice: nil, alert: nil)
    turbo_stream.replace("flash", partial: "layouts/flash", locals: { notice: notice, alert: alert })
  end

  def start_request_timer
    Current.started_at = Time.current
  end

  # So the timeline can record who moved a ticket without every call site
  # having to pass an author around.
  def remember_who_is_acting
    Current.user = current_user
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def admin?
    current_user&.admin? || false
  end

  # Someone who runs a queue of their own: tickets can be filed to them, and
  # they can triage what lands there.
  def owner?
    current_user&.receives_tickets? || false
  end

  def manages?(ticket)
    ticket.managed_by?(current_user)
  end

  # Your queue is what's filed TO you — work you have to do. What you've
  # asked of other people is a different question, and belongs under its own
  # heading rather than mixed into the queue. Someone who takes no tickets
  # has only ever asked, so that's all they see.
  def visible_tickets
    return Ticket.all if everyone?
    return Ticket.where(user_id: current_user.id) if filed_by_me?

    Ticket.owned_by(current_user)
  end

  def everyone?
    admin? && params[:scope] == "everyone"
  end

  # How much is on your plate, by status — one query, shared by the badge in
  # the nav, the tab title, the favicon and the dashboard heading. Nil for
  # someone who takes no tickets, since there's nothing to count.
  def queue_counts
    return unless owner?

    @queue_counts ||= begin
      counts = Ticket.owned_by(current_user).needs_attention.group(:status).count
      { open: counts.fetch("open", 0), in_progress: counts.fetch("in_progress", 0) }
    end
  end

  def filed_by_me?
    params[:scope] == "filed" || !owner?
  end

  # What the search reaches: your queue and anything you filed. An admin can
  # open anybody's ticket by its link, but has to go looking for it rather
  # than having it turn up while searching their own.
  def readable_tickets
    Ticket.where(owner_id: current_user.id).or(Ticket.where(user_id: current_user.id))
  end

  def require_login
    return if current_user

    # Remembered so signing in lands you where you were headed — which the
    # OAuth consent screen depends on.
    session[:return_to] = request.fullpath if request.get? || request.head?
    redirect_to root_path, alert: "Please sign in to continue."
  end

  def require_admin!
    return if admin?

    redirect_to root_path, alert: "You don't have access to that."
  end

  def require_owner!
    return if owner?

    redirect_to root_path, alert: "You don't have a ticket queue of your own."
  end
end
