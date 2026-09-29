# Links one ticket to another it's waiting on. Admin-only: choosing a blocker
# means picking from everyone's tickets, which requesters can't see.
class TicketBlocksController < ApplicationController
  include TicketStreams

  before_action :set_ticket
  before_action :require_manage!

  def create
    link = @ticket.blocked_links.new(blocker_ticket_id: params[:blocker_ticket_id])

    if link.save
      respond(notice: "#{@ticket.reference} is now waiting on #{link.blocker_ticket.reference}.")
    else
      respond(alert: link.errors.full_messages.to_sentence)
    end
  end

  def destroy
    link = @ticket.blocked_links.find(params[:id])
    link.destroy

    respond(notice: "#{@ticket.reference} is no longer waiting on #{link.blocker_ticket.reference}.")
  end

  private

  def respond(notice: nil, alert: nil)
    respond_to do |format|
      format.turbo_stream do
        streams = [ flash_stream(notice: notice, alert: alert) ]
        streams += scheduling_streams(@ticket.reload) if alert.nil?

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
