class TicketDeadlinesController < ApplicationController
  include TicketStreams

  before_action :set_ticket
  before_action :require_manage!

  def update
    due = params.dig(:ticket, :due_at)

    if @ticket.update(due_at: due)
      respond(notice: due.present? ? "Deadline set to #{@ticket.due_on}." : "Deadline cleared.")
    else
      respond(alert: @ticket.errors.full_messages.to_sentence)
    end
  end

  def destroy
    @ticket.update(due_at: nil)
    respond(notice: "Deadline cleared.")
  end

  private

  def respond(notice: nil, alert: nil)
    respond_to do |format|
      format.turbo_stream do
        streams = [ flash_stream(notice: notice, alert: alert) ]
        streams += scheduling_streams(@ticket) if alert.nil?

        render turbo_stream: streams
      end
      format.html { redirect_to @ticket, notice: notice, alert: alert }
    end
  end

  def set_ticket
    @ticket = Ticket.find(params[:ticket_id])
  end

  def require_manage!
    return if manages?(@ticket)

    redirect_to root_path, alert: "You don't have access to that ticket."
  end
end
