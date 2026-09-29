class DashboardController < ApplicationController
  skip_before_action :require_login

  def index
    return unless current_user

    if owner?
      @tickets = Ticket.owned_by(current_user).needs_attention.ordered_for_admin
                       .includes(:user, :service, :topic, :blockers)
    else
      @tickets = current_user.tickets.order(created_at: :desc).includes(:service, :topic, :blockers)
    end
  end
end
