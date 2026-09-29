# Posting to a ticket's timeline: a message to the other side, a private note,
# or just a file.
class TicketEventsController < ApplicationController
  include TicketStreams

  before_action :set_ticket
  before_action :require_access!

  def create
    @event = @ticket.events.new(event_params.merge(author: current_user, kind: kind))
    saved = @event.save

    respond_to do |format|
      format.turbo_stream do
        streams = [ saved ? flash_stream(notice: "#{@event.internal_note? ? 'Note' : 'Message'} added.") : flash_stream(alert: @event.errors.full_messages.to_sentence) ]
        # The composer is re-rendered either way: on success to clear it, on
        # failure so it isn't left half-submitted.
        streams << turbo_stream.replace(helpers.dom_id(@ticket, :composer), partial: "tickets/composer", locals: { ticket: @ticket })
        streams << turbo_stream.append(helpers.dom_id(@ticket, :timeline), partial: "tickets/event", locals: { event: @event }) if saved

        render turbo_stream: streams
      end

      format.html do
        saved ? redirect_to(@ticket) : redirect_to(@ticket, alert: @event.errors.full_messages.to_sentence)
      end
    end
  end

  def destroy
    event = @ticket.events.find(params[:id])

    unless event.author_id == current_user.id || admin?
      return redirect_to @ticket, alert: "That isn't yours to delete."
    end

    event.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [ turbo_stream.remove(helpers.dom_id(event)), flash_stream(notice: "Deleted.") ]
      end
      format.html { redirect_to @ticket, notice: "Deleted." }
    end
  end

  private

  # A private note is only an option for whoever the ticket is for; everyone
  # else writes to the thread both sides can read.
  def kind
    params[:internal] == "1" && manages?(@ticket) ? :internal_note : :comment
  end

  def event_params
    params.expect(ticket_event: [ :body, files: [] ])
  end

  def set_ticket
    @ticket = Ticket.find(params[:ticket_id])
  end

  def require_access!
    return if @ticket.visible_to?(current_user)

    redirect_to root_path, alert: "You don't have access to that ticket."
  end
end
