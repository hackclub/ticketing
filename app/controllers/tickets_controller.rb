class TicketsController < ApplicationController
  include TicketStreams

  before_action :set_ticket, only: [ :show, :update ]
  before_action :authorize_ticket!, only: [ :show, :update ]

  # Tabs rather than a status dropdown: "what's live" and "what's finished"
  # are the only two questions anyone actually asks of a ticket list.
  FILTERS = {
    "open" => "Open",
    "closed" => "Closed",
    "all" => "All"
  }.freeze

  def index
    @filter = FILTERS.key?(params[:status]) ? params[:status] : "open"
    @tickets = filtered_tickets
  end

  def new
    @ticket = Ticket.new
    @services = Service.fileable.fallback_last
  end

  def create
    @ticket = current_user.tickets.new(ticket_params)

    if @ticket.save
      redirect_to @ticket, notice: "Ticket submitted."
    else
      @services = Service.fileable.fallback_last
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @events = @ticket.events.oldest_first.includes(:author, files_attachments: :blob)
                     .select { |event| event.visible_to?(current_user) }
  end

  def update
    unless manages?(@ticket)
      return redirect_to @ticket, alert: "Only the person a ticket is for can update its status."
    end

    status = status_params[:status]

    # Assigning an unknown value to an enum raises rather than failing
    # validation, so a stale form or a hand-rolled request would 500.
    unless Ticket.statuses.key?(status)
      return respond_with_status_change(false, error: "#{status.inspect} isn't a status")
    end

    # The note is assigned even when the form didn't send one, so a quick status
    # change from the dashboard clears a stale note rather than re-sending it.
    updated = @ticket.update(status: status, status_note: params.dig(:ticket, :status_note))

    respond_with_status_change(updated, error: @ticket.errors.full_messages.to_sentence)
  end

  private

  # Admins see everyone's; everyone else sees their own. Open tickets keep
  # the queue's ordering (blocked last, deadlines first); closed ones are
  # most-recently-touched first, which is how you look for what you just did.
  def filtered_tickets
    scope = visible_tickets.includes(:user, :owner, :service, :topic, :blockers)

    case @filter
    when "open" then owner? ? scope.needs_attention.ordered_for_admin : scope.needs_attention.order(created_at: :desc)
    when "closed" then scope.closed.order(updated_at: :desc)
    else scope.order(created_at: :desc)
    end
  end

  def respond_with_status_change(updated, error:)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: status_streams(updated, error) }
      format.html do
        updated ? redirect_to(request.referer.presence || @ticket, notice: "Ticket updated.")
                : redirect_to(@ticket, alert: error)
      end
    end
  end

  # Sent to both pages that can change a status: the ticket page gets its
  # badge/note/form back and the dashboard gets its queue re-rendered.
  def status_streams(updated, error)
    streams = [ updated ? flash_stream(notice: "Ticket updated.") : flash_stream(alert: error) ]
    return streams unless updated

    streams + [
      turbo_stream.replace(helpers.dom_id(@ticket, :status), partial: "tickets/status_badge", locals: { ticket: @ticket }),
      turbo_stream.replace(helpers.dom_id(@ticket, :status_form), partial: "tickets/status_form", locals: { ticket: @ticket }),
      turbo_stream.append(helpers.dom_id(@ticket, :timeline), partial: "tickets/event",
                          locals: { event: @ticket.events.oldest_first.last }),
      turbo_stream.replace(helpers.dom_id(@ticket, :row), partial: "tickets/row", locals: { ticket: @ticket }),
      # Finishing a ticket can unblock others, and a closed ticket stops
      # being overdue, so the scheduling box and its badge move too.
      *scheduling_streams(@ticket)
    ]
  end

  def set_ticket
    @ticket = Ticket.find(params[:id])
  end

  def authorize_ticket!
    return if @ticket.visible_to?(current_user)

    redirect_to root_path, alert: "You don't have access to that ticket."
  end

  def ticket_params
    params.expect(ticket: [ :title, :service_id, :topic_id, :url, :priority, :message, :due_at ])
  end

  def status_params
    params.expect(ticket: [ :status ])
  end
end
