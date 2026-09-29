class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :start_request_timer
  before_action :require_login
  before_action :remember_who_is_acting

  helper_method :current_user, :admin?, :owner?, :manages?, :everyone?

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

  # Everybody, admins included, sees their own queue: what's filed to them
  # plus what they filed. An admin can ask for everyone's, but has to ask —
  # running the tracker isn't a reason to have other people's work in the
  # way of your own.
  def visible_tickets
    return Ticket.all if everyone?

    Ticket.where(owner_id: current_user.id).or(Ticket.where(user_id: current_user.id))
  end

  def everyone?
    admin? && params[:scope] == "everyone"
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
