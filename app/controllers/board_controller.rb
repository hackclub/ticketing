# The same tickets as the index, arranged as a board: a column per status,
# with the ones you're responsible for draggable between them.
class BoardController < ApplicationController
  # Finished columns would grow forever otherwise, and nobody scrolls them.
  CLOSED_SHOWN = 25

  def index
    @columns = Ticket.statuses.keys.index_with { |status| tickets_in(status) }
  end

  private

  def tickets_in(status)
    scope = visible_tickets.where(status: status).includes(:user, :owner, :service, :topic, :blockers)

    if Ticket.new(status: status).needs_attention?
      owner? ? scope.ordered_for_admin : scope.order(created_at: :desc)
    else
      scope.order(updated_at: :desc).limit(CLOSED_SHOWN)
    end
  end

  def visible_tickets
    return Ticket.all if admin?

    Ticket.where(owner_id: current_user.id).or(Ticket.where(user_id: current_user.id))
  end
end
