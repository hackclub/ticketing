# The same tickets as the index, arranged as a board: a column per status,
# with the ones you're responsible for draggable between them.
class BoardController < ApplicationController
  # Finished columns would grow forever otherwise, and nobody scrolls them.
  CLOSED_SHOWN = 25

  # Two loads for the whole board — one for what's live, one for what's
  # finished — rather than one per column.
  def index
    @columns = Ticket.statuses.keys.index_with { [] }

    live.each { |ticket| @columns[ticket.status] << ticket }
    finished.group_by(&:status).each { |status, tickets| @columns[status] = tickets.first(CLOSED_SHOWN) }
  end

  private

  def live
    scope = visible_tickets.needs_attention.preload(:user, :owner, :service, :topic, :blockers)
    owner? ? scope.ordered_for_admin : scope.order(created_at: :desc)
  end

  def finished
    visible_tickets.closed.preload(:user, :owner, :service, :topic, :blockers)
                   .order(updated_at: :desc).limit(CLOSED_SHOWN * Ticket.statuses.size)
  end

  def visible_tickets
    return Ticket.all if admin?

    Ticket.where(owner_id: current_user.id).or(Ticket.where(user_id: current_user.id))
  end
end
