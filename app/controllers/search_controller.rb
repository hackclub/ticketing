# Backs the ⌘K palette: the tickets and people you might be looking for, plus
# the handful of places you might want to jump to. Everything is scoped to
# whoever is asking — an admin searches every ticket, anyone else only theirs.
class SearchController < ApplicationController
  TICKET_LIMIT = 6
  PERSON_LIMIT = 4

  def index
    @term = params[:q].to_s.strip
    @tickets = matching_tickets
    @people = admin? ? matching_people : User.none
    @destinations = matching_destinations

    # Inside the palette this is a frame, so it needs no chrome. Straight to
    # /search it's an ordinary page, which is also the fallback when the
    # palette's JavaScript never arrives.
    render layout: !turbo_frame_request?
  end

  private

  def matching_tickets
    scope = (everyone? ? Ticket.all : readable_tickets).includes(:user, :owner, :service, :topic, :blockers)

    # An empty box is a launcher, not a dead end: show what's been touched most
    # recently, since that's usually what you came back for.
    return scope.order(updated_at: :desc).limit(TICKET_LIMIT) if @term.blank?

    # "#42" and "42" are how people refer to a ticket, so try that first.
    if (id = @term[/\A#?(\d+)\z/, 1]) && (exact = scope.where(id: id)).any?
      return exact
    end

    scope.where("tickets.title ILIKE :like OR tickets.message ILIKE :like", like: like)
         .order(Arel.sql(title_matches_first))
         .limit(TICKET_LIMIT)
  end

  def matching_people
    return User.none if @term.blank?

    User.where("users.name ILIKE :like OR users.email ILIKE :like", like: like).order(:name).limit(PERSON_LIMIT)
  end

  def matching_destinations
    list = [
      [ "Dashboard", root_path ],
      [ "New ticket", new_ticket_path ],
      [ "Board", board_path ],
      [ "Open tickets", tickets_path(status: "open") ],
      [ "Closed tickets", tickets_path(status: "closed") ],
      [ "All tickets", tickets_path(status: "all") ],
      [ "Tickets you filed", tickets_path(scope: "filed", status: "all") ],
      [ "Settings", settings_path ]
    ]
    list << [ "Services & topics", services_path ] if owner?
    list << [ "People", admin_users_path ] if admin?

    return list if @term.blank?

    list.select { |label, _path| label.downcase.include?(@term.downcase) }
  end

  # A title hit is what you meant; a body hit is usually incidental.
  def title_matches_first
    Ticket.sanitize_sql_array([ "CASE WHEN tickets.title ILIKE ? THEN 0 ELSE 1 END, tickets.updated_at DESC", like ])
  end

  def like
    @like ||= "%#{Ticket.sanitize_sql_like(@term)}%"
  end
end
