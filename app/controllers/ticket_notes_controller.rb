class TicketNotesController < ApplicationController
  before_action :set_ticket
  before_action :require_manage!

  def create
    @note = @ticket.notes.new(body: params.dig(:ticket_note, :body), author: current_user)
    saved = @note.save

    respond_to do |format|
      format.turbo_stream do
        streams = [ saved ? flash_stream(notice: "Note added.") : flash_stream(alert: @note.errors.full_messages.to_sentence) ]
        # The form is re-rendered either way: on success to clear it, on
        # failure so the textarea isn't left in a half-submitted state.
        streams << turbo_stream.replace(helpers.dom_id(@ticket, :note_form), partial: "tickets/note_form", locals: { ticket: @ticket })
        streams << turbo_stream.append(helpers.dom_id(@ticket, :notes), partial: "tickets/note", locals: { note: @note }) if saved

        render turbo_stream: streams
      end

      format.html do
        saved ? redirect_to(@ticket, notice: "Note added.") : redirect_to(@ticket, alert: @note.errors.full_messages.to_sentence)
      end
    end
  end

  def destroy
    note = @ticket.notes.find(params[:id])
    note.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [ turbo_stream.remove(helpers.dom_id(note)), flash_stream(notice: "Note deleted.") ]
      end
      format.html { redirect_to @ticket, notice: "Note deleted." }
    end
  end

  private

  def set_ticket
    @ticket = Ticket.find(params[:ticket_id])
  end

  def require_manage!
    return if manages?(@ticket)

    redirect_to root_path, alert: "You don't have access to that ticket."
  end
end
