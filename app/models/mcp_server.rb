# A Model Context Protocol server over JSON-RPC, so tickets can be filed and
# triaged from inside an AI client. Every call is scoped to the user whose API
# token authenticated the request; admin-only tools are hidden from everyone else.
class McpServer
  PROTOCOL_VERSION = "2025-06-18".freeze
  SUPPORTED_PROTOCOL_VERSIONS = [ PROTOCOL_VERSION, "2025-03-26", "2024-11-05" ].freeze

  DUE_FORMAT = "Optional deadline as an ISO 8601 timestamp, e.g. 2026-10-01T17:00:00Z. " \
               "Work out relative dates like \"next Friday\" yourself — they aren't parsed here. " \
               "A time with no zone is read in the tracker's own zone.".freeze

  PARSE_ERROR = -32700
  INVALID_REQUEST = -32600
  METHOD_NOT_FOUND = -32601
  INVALID_PARAMS = -32602
  INTERNAL_ERROR = -32603

  def initialize(user)
    @user = user
  end

  # Returns a JSON-RPC response hash, or nil for notifications (which get no reply).
  def handle(message)
    return error(nil, INVALID_REQUEST, "Invalid request") unless message.is_a?(Hash)

    id = message["id"]
    params = message["params"] || {}

    case message["method"]
    when "initialize" then success(id, initialize_result(params))
    when "ping" then success(id, {})
    when "tools/list" then success(id, { "tools" => tools })
    when "tools/call" then success(id, call_tool(params))
    when /\Anotifications\// then nil
    else
      id.nil? ? nil : error(id, METHOD_NOT_FOUND, "Unknown method: #{message['method']}")
    end
  rescue ActiveRecord::RecordNotFound
    error(id, INVALID_PARAMS, "No such ticket")
  rescue StandardError => e
    Rails.logger.error("MCP error: #{e.class}: #{e.message}")
    error(id, INTERNAL_ERROR, e.message)
  end

  private

  attr_reader :user

  def initialize_result(params)
    requested = params["protocolVersion"]

    {
      "protocolVersion" => SUPPORTED_PROTOCOL_VERSIONS.include?(requested) ? requested : PROTOCOL_VERSION,
      "capabilities" => { "tools" => { "listChanged" => false } },
      "serverInfo" => { "name" => "tickets", "version" => AppRevision.sha },
      "instructions" => "Tickets for #{ENV.fetch('APP_HOST', 'this app')}. " \
                        "Call list_services before create_ticket so you use a real service and topic."
    }
  end

  def tools
    list = [
      {
        "name" => "list_services",
        "description" => "List the services and their topics that a ticket can be filed under. " \
                         "Call this before create_ticket.",
        "inputSchema" => { "type" => "object", "properties" => {} }
      },
      {
        "name" => "create_ticket",
        "description" => "File a new ticket. Service and topic must come from list_services; the service decides " \
                         "whose queue it lands in, so pick one belonging to the person you want it done by.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "title" => { "type" => "string", "description" => "Short summary of the request" },
            "service" => { "type" => "string", "description" => "Service name, e.g. Website" },
            "topic" => { "type" => "string", "description" => "Topic name within that service, e.g. Bug" },
            "message" => { "type" => "string", "description" => "The details. Markdown is supported." },
            "priority" => { "type" => "string", "enum" => Ticket.priorities.keys, "description" => "Defaults to #{Ticket.new.priority}" },
            "url" => { "type" => "string", "description" => "Optional link to something relevant" },
            "due" => { "type" => "string", "description" => DUE_FORMAT },
            "for" => { "type" => "string", "description" => "Only needed when two people have a service by the " \
                                                            "same name: whose one you mean, by name or email" }
          },
          "required" => [ "title", "service", "topic", "message" ]
        }
      },
      {
        "name" => "list_my_tickets",
        "description" => "List tickets you filed, newest first.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "status" => { "type" => "string", "enum" => Ticket.statuses.keys + [ "all" ], "description" => "Defaults to all" }
          }
        }
      },
      {
        "name" => "add_comment",
        "description" => "Say something on a ticket's timeline. This is a message to the other side: the person " \
                         "it's for if you filed it, the person who filed it if it's yours. They get an email and " \
                         "a Slack DM. For something private use add_internal_note instead.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "id" => { "type" => "integer" },
            "message" => { "type" => "string", "description" => "Markdown is supported." }
          },
          "required" => [ "id", "message" ]
        }
      },
      {
        "name" => "get_ticket",
        "description" => "Get one ticket in full, including everything on its timeline.",
        "inputSchema" => {
          "type" => "object",
          "properties" => { "id" => { "type" => "integer" } },
          "required" => [ "id" ]
        }
      }
    ]

    list + (user.receives_tickets? ? queue_tools : []) + (user.admin? ? admin_tools : [])
  end

  # Anyone who takes tickets gets these, against their own queue.
  def queue_tools
    [
      {
        "name" => "my_queue",
        "description" => "Everything waiting on you: the open and in-progress tickets filed to you. " \
                         "Anything blocked by an unfinished ticket sinks to the bottom, near deadlines rise to " \
                         "the top, and VIP requesters and higher priority break the ties.",
        "inputSchema" => {
          "type" => "object",
          "properties" => { "limit" => { "type" => "integer", "description" => "Defaults to 25" } }
        }
      },
      {
        "name" => "add_internal_note",
        "description" => "Add a private working note to a ticket. Only admins ever see these — the requester " \
                         "is not emailed or DM'd. Use this for anything you wouldn't say to them directly. " \
                         "Notes append, so this never overwrites an earlier one.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "id" => { "type" => "integer", "description" => "Ticket id" },
            "note" => { "type" => "string", "description" => "The note. Markdown is supported." }
          },
          "required" => [ "id", "note" ]
        }
      },
      {
        "name" => "update_ticket_status",
        "description" => "Change a ticket's status. WARNING: the optional note here is SENT to the requester by " \
                         "email and Slack DM — for a private note use add_internal_note instead.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "id" => { "type" => "integer" },
            "status" => { "type" => "string", "enum" => Ticket.statuses.keys },
            "note" => { "type" => "string", "description" => "Optional explanation sent to the requester" }
          },
          "required" => [ "id", "status" ]
        }
      },
      {
        "name" => "set_deadline",
        "description" => "Set a ticket's deadline, or clear it by calling with no due. Deadlines that are " \
                         "close or already past pull a ticket up my_queue. This notifies nobody.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "id" => { "type" => "integer" },
            "due" => { "type" => "string", "description" => DUE_FORMAT }
          },
          "required" => [ "id" ]
        }
      },
      {
        "name" => "block_ticket",
        "description" => "Record that a ticket can't move until another one is finished. A blocked ticket sinks " \
                         "to the bottom of my_queue until what it's waiting on is done or won't-do. Chains are " \
                         "fine — x can wait on y which waits on f — but a loop is rejected.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "id" => { "type" => "integer", "description" => "The ticket that is stuck" },
            "blocked_by" => { "type" => "integer", "description" => "The ticket it is waiting on" }
          },
          "required" => [ "id", "blocked_by" ]
        }
      },
      {
        "name" => "unblock_ticket",
        "description" => "Remove a link added by block_ticket. Finishing the blocker is usually better — that " \
                         "clears the way without losing the record of why it was stuck.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "id" => { "type" => "integer" },
            "blocked_by" => { "type" => "integer", "description" => "The ticket it should stop waiting on" }
          },
          "required" => [ "id", "blocked_by" ]
        }
      },
      {
        "name" => "set_priority",
        "description" => "Change a ticket's priority. Unlike a status change, this notifies nobody.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "id" => { "type" => "integer" },
            "priority" => { "type" => "string", "enum" => Ticket.priorities.keys }
          },
          "required" => [ "id", "priority" ]
        }
      },
      {
        "name" => "create_service",
        "description" => "Add one of your own services that tickets can be filed under, optionally with its first topics.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "name" => { "type" => "string" },
            "topics" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Optional topic names to create under it" }
          },
          "required" => [ "name" ]
        }
      },
      {
        "name" => "update_service",
        "description" => "Rename a service, or retire it by setting active to false — retiring hides it from the " \
                         "new-ticket form while keeping existing tickets intact. Deleting is web-only, on purpose.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "name" => { "type" => "string", "description" => "The service to change" },
            "new_name" => { "type" => "string" },
            "active" => { "type" => "boolean" }
          },
          "required" => [ "name" ]
        }
      },
      {
        "name" => "create_topic",
        "description" => "Add a topic under an existing service.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "service" => { "type" => "string" },
            "name" => { "type" => "string" }
          },
          "required" => [ "service", "name" ]
        }
      },
      {
        "name" => "update_topic",
        "description" => "Rename a topic, or retire it by setting active to false. Deleting is web-only, on purpose.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "service" => { "type" => "string" },
            "name" => { "type" => "string", "description" => "The topic to change" },
            "new_name" => { "type" => "string" },
            "active" => { "type" => "boolean" }
          },
          "required" => [ "service", "name" ]
        }
      }
    ]
  end

  # Running the tracker itself, rather than a queue in it.
  def admin_tools
    [
      {
        "name" => "list_people",
        "description" => "Everyone who has used the tracker, with their ticket counts, whether they're a VIP, " \
                         "and whether they have a queue of their own.",
        "inputSchema" => { "type" => "object", "properties" => {} }
      },
      {
        "name" => "set_vip",
        "description" => "Mark someone as a VIP, or unmark them. VIPs' tickets sort to the top of my_queue and " \
                         "the dashboard. Identify them by name or email as shown in list_people.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "person" => { "type" => "string", "description" => "Name or email from list_people" },
            "vip" => { "type" => "boolean", "description" => "True to mark, false to unmark" }
          },
          "required" => [ "person", "vip" ]
        }
      },
      {
        "name" => "enable_tickets",
        "description" => "Let someone use the tracker for themselves, or stop them. Enabled, they get a queue of " \
                         "their own: people can file tickets to them, they can file their own, and Slack and " \
                         "these tools start working against their tickets. They're given a catch-all service to " \
                         "start with so they can be filed to straight away.",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "person" => { "type" => "string", "description" => "Name or email from list_people" },
            "enabled" => { "type" => "boolean", "description" => "True to let them in, false to switch them off" }
          },
          "required" => [ "person", "enabled" ]
        }
      }
    ]
  end

  def call_tool(params)
    name = params["name"]
    args = params["arguments"] || {}

    return tool_error("Unknown tool: #{name}") unless tools.any? { |tool| tool["name"] == name }

    text = case name
    when "list_services" then list_services
    when "create_ticket" then create_ticket(args)
    when "list_my_tickets" then list_my_tickets(args)
    when "get_ticket" then get_ticket(args)
    when "add_comment" then add_comment(args)
    when "my_queue" then my_queue(args)
    when "add_internal_note" then add_internal_note(args)
    when "update_ticket_status" then update_ticket_status(args)
    when "list_people" then list_people
    when "set_vip" then set_vip(args)
    when "enable_tickets" then enable_tickets(args)
    when "set_priority" then set_priority(args)
    when "set_deadline" then set_deadline(args)
    when "block_ticket" then block_ticket(args)
    when "unblock_ticket" then unblock_ticket(args)
    when "create_service" then create_service(args)
    when "update_service" then update_service(args)
    when "create_topic" then create_topic(args)
    when "update_topic" then update_topic(args)
    end

    text.is_a?(Array) ? tool_error(text.first) : tool_result(text)
  end

  # --- tools -------------------------------------------------------------

  # Whoever owns the service is who the ticket goes to, so the list is
  # grouped by person. You also see your own retired entries, since you're
  # the one who retired them.
  def list_services
    services = Service.fileable.fallback_last.to_a
    services |= user.services.fallback_last.includes(:topics, :owner).to_a if user.receives_tickets?
    return "Nobody is taking tickets yet." if services.empty?

    Service.grouped_by_owner(services).map do |owner, owned|
      lines = owned.map { |service| "  #{describe_service(service)}" }
      "#{owner.display_name}#{' (you)' if owner == user}:\n#{lines.join("\n")}"
    end.join("\n")
  end

  def describe_service(service)
    mine = service.owner_id == user.id
    topics = service.topics.select { |topic| topic.active? || mine }
                    .map { |topic| topic.active? ? topic.name : "#{topic.name} (retired)" }

    label = service.active? ? service.name : "#{service.name} (retired)"
    "#{label}: #{topics.any? ? topics.join(', ') : '(no topics yet)'}"
  end

  def create_ticket(args)
    services = Service.fileable.where("LOWER(services.name) = ?", args["service"].to_s.downcase).to_a
    services = narrow_by_owner(services, args["for"]) if args["for"].present?

    return [ "No service called #{args['service'].inspect}. Available:\n#{list_services}" ] if services.empty?

    if services.size > 1
      owners = services.map { |candidate| candidate.owner.display_name }.join(", ")
      return [ "#{args['service'].inspect} belongs to more than one person (#{owners}). Say which with \"for\"." ]
    end

    service = services.first
    topic = service.topics.active.find_by("LOWER(name) = ?", args["topic"].to_s.downcase)
    return [ "#{service.name} has no topic called #{args['topic'].inspect}. Available:\n#{list_services}" ] if topic.nil?

    ticket = user.tickets.new(
      title: args["title"],
      message: args["message"],
      service: service,
      topic: topic,
      priority: args["priority"].presence || Ticket.new.priority,
      url: args["url"].presence
    )

    if args["due"].present?
      due = parse_time(args["due"])
      return [ "Could not read #{args['due'].inspect} as a date. #{DUE_FORMAT}" ] if due.nil?

      ticket.due_at = due
    end

    return [ "Could not file it: #{ticket.errors.full_messages.to_sentence}" ] unless ticket.save

    "Filed ticket ##{ticket.id} for #{ticket.owner.display_name}.\n\n#{describe(ticket)}"
  end

  def narrow_by_owner(services, person)
    needle = person.to_s.downcase.strip
    services.select do |service|
      service.owner.display_name.downcase.include?(needle) || service.owner.email.downcase == needle
    end
  end

  def list_my_tickets(args)
    scope = user.tickets.includes(:service, :topic).order(created_at: :desc)
    status = args["status"].presence
    scope = scope.where(status: status) if status && status != "all"

    return "You have no #{status == 'all' ? '' : "#{status} "}tickets." if scope.empty?

    scope.map { |ticket| summarize(ticket) }.join("\n")
  end

  def get_ticket(args)
    ticket = Ticket.find(args["id"])
    return [ "You don't have access to ticket ##{ticket.id}." ] unless ticket.visible_to?(user)

    describe(ticket, full: true)
  end

  # Whoever a ticket is for is the only one who can act on it (bar an admin).
  def manage(id)
    ticket = Ticket.find(id)
    return [ nil, [ "Ticket ##{ticket.id} isn't yours to change — it's for #{ticket.owner.display_name}." ] ] unless ticket.managed_by?(user)

    [ ticket, nil ]
  end

  def add_comment(args)
    ticket = Ticket.find(args["id"])
    return [ "You don't have access to ticket ##{ticket.id}." ] unless ticket.visible_to?(user)

    event = ticket.events.new(kind: :comment, body: args["message"], author: user)
    return [ "Could not add it: #{event.errors.full_messages.to_sentence}" ] unless event.save

    "Added to ##{ticket.id}. #{ticket.other_party(user).display_name} gets an email and a Slack DM."
  end

  def my_queue(args)
    limit = [ args["limit"].to_i, 1 ].max
    limit = 25 if args["limit"].blank?

    tickets = Ticket.owned_by(user).needs_attention.ordered_for_admin
                    .includes(:user, :service, :topic, :blockers).limit(limit)
    return "Nothing outstanding. 🎉" if tickets.empty?

    "#{tickets.size} waiting on you:\n" + tickets.map { |ticket| summarize(ticket, requester: true) }.join("\n")
  end

  def add_internal_note(args)
    ticket, refusal = manage(args["id"])
    return refusal if refusal
    note = ticket.events.new(kind: :internal_note, body: args["note"], author: user)

    return [ "Could not add it: #{note.errors.full_messages.to_sentence}" ] unless note.save

    count = ticket.events.internal_note.count
    "Added a private note to ##{ticket.id}. It has #{count} #{'note'.pluralize(count)} now."
  end

  def update_ticket_status(args)
    ticket, refusal = manage(args["id"])
    return refusal if refusal

    # Assigning an unknown enum value raises, so check before it reaches the model.
    unless Ticket.statuses.key?(args["status"])
      return [ "#{args['status'].inspect} isn't a status. Valid: #{Ticket.statuses.keys.join(', ')}." ]
    end

    unless ticket.update(status: args["status"], status_note: args["note"].presence)
      return [ "Could not update it: #{ticket.errors.full_messages.to_sentence}" ]
    end

    notified = ticket.user.slack_id.present? ? " #{ticket.user.name.presence || 'They'} will get an email and a Slack DM." : " They'll get an email."
    "Ticket ##{ticket.id} is now #{ticket.status_sentence}.#{notified}"
  end

  def list_people
    people = User.left_joins(:tickets).group(:id).order(:name)
                 .pluck(:name, :email, :priority_boost, :admin, :receives_tickets, Arel.sql("COUNT(tickets.id)"))
    return "Nobody has used the tracker yet." if people.empty?

    people.map do |name, email, vip, admin, receives, count|
      tags = [ ("VIP" if vip), ("admin" if admin), ("takes tickets" if receives && !admin) ].compact
      "- #{name.presence || email} (#{email})#{" [#{tags.join(', ')}]" if tags.any?} — #{count} #{'ticket'.pluralize(count)}"
    end.join("\n")
  end

  def set_vip(args)
    person, refusal = find_person(args["person"])
    return refusal if refusal

    person.update!(priority_boost: args["vip"])

    "#{person.name.presence || person.email} is #{person.priority_boost? ? 'now a VIP — their tickets sort to the top' : 'no longer a VIP'}."
  end

  def enable_tickets(args)
    person, refusal = find_person(args["person"])
    return refusal if refusal

    if ActiveModel::Type::Boolean.new.cast(args["enabled"])
      person.start_receiving_tickets!
      "#{person.display_name} can use the tracker now. They have a catch-all service, so they can be filed to " \
        "straight away — they'll want to add their own services on the web."
    else
      person.stop_receiving_tickets!
      "#{person.display_name} no longer takes tickets. Nothing new can be filed to them; what they already have stays put."
    end
  end

  def set_priority(args)
    ticket, refusal = manage(args["id"])
    return refusal if refusal

    unless Ticket.priorities.key?(args["priority"])
      return [ "#{args['priority'].inspect} isn't a priority. Valid: #{Ticket.priorities.keys.join(', ')}." ]
    end

    ticket.update!(priority: args["priority"])
    "Ticket ##{ticket.id} is now #{ticket.priority} priority."
  end

  def create_service(args)
    service = user.services.new(name: args["name"].to_s.strip)
    return [ "Could not create it: #{service.errors.full_messages.to_sentence}" ] unless service.save

    topics = Array(args["topics"]).map(&:to_s).map(&:strip).reject(&:empty?)
    created = topics.filter_map { |name| service.topics.create(name: name).persisted? ? name : nil }

    "Created service #{service.name}." +
      (created.any? ? " Topics: #{created.join(', ')}." : " It has no topics yet — add some before anyone can file under it.")
  end

  def update_service(args)
    service = find_service(args["name"])
    return [ "No service called #{args['name'].inspect}. Available:\n#{list_services}" ] if service.nil?

    service.name = args["new_name"].to_s.strip if args["new_name"].present?
    service.active = args["active"] unless args["active"].nil?

    return [ "Could not update it: #{service.errors.full_messages.to_sentence}" ] unless service.save

    "#{service.name} is now #{service.active? ? 'active' : 'retired (hidden from the new-ticket form)'}."
  end

  def create_topic(args)
    service = find_service(args["service"])
    return [ "No service called #{args['service'].inspect}. Available:\n#{list_services}" ] if service.nil?

    topic = service.topics.new(name: args["name"].to_s.strip)
    return [ "Could not create it: #{topic.errors.full_messages.to_sentence}" ] unless topic.save

    "Added #{topic.name} under #{service.name}."
  end

  def update_topic(args)
    service = find_service(args["service"])
    return [ "No service called #{args['service'].inspect}. Available:\n#{list_services}" ] if service.nil?

    topic = service.topics.find_by("LOWER(name) = ?", args["name"].to_s.downcase.strip)
    return [ "#{service.name} has no topic called #{args['name'].inspect}." ] if topic.nil?

    topic.name = args["new_name"].to_s.strip if args["new_name"].present?
    topic.active = args["active"] unless args["active"].nil?

    return [ "Could not update it: #{topic.errors.full_messages.to_sentence}" ] unless topic.save

    "#{service.name} > #{topic.name} is now #{topic.active? ? 'active' : 'retired'}."
  end

  def set_deadline(args)
    ticket, refusal = manage(args["id"])
    return refusal if refusal

    if args["due"].blank?
      ticket.update!(due_at: nil)
      return "Ticket ##{ticket.id} no longer has a deadline."
    end

    due = parse_time(args["due"])
    return [ "Could not read #{args['due'].inspect} as a date. #{DUE_FORMAT}" ] if due.nil?

    ticket.update!(due_at: due)
    "Ticket ##{ticket.id} is due #{ticket.due_on} — #{ticket.due_label}."
  end

  def block_ticket(args)
    ticket, refusal = manage(args["id"])
    return refusal if refusal

    blocker, blocker_refusal = manage(args["blocked_by"])
    return blocker_refusal if blocker_refusal
    link = ticket.blocked_links.new(blocker_ticket: blocker)

    return [ "Could not link them: #{link.errors.full_messages.to_sentence}" ] unless link.save

    "#{ticket.reference} is now waiting on #{blocker.reference}." +
      (blocker.needs_attention? ? " It'll sit at the bottom of my_queue until that's finished." : "")
  end

  def unblock_ticket(args)
    ticket, refusal = manage(args["id"])
    return refusal if refusal
    link = ticket.blocked_links.find_by(blocker_ticket_id: args["blocked_by"])

    return [ "Ticket ##{ticket.id} isn't waiting on ##{args['blocked_by']}." ] if link.nil?

    link.destroy
    "#{ticket.reference} is no longer waiting on ##{args['blocked_by']}."
  end

  # Time.zone.parse is lenient enough to find a date in almost anything —
  # "next Friday-ish" comes back as this coming Friday — so the shape is
  # checked first. A client that can't produce a real timestamp should be
  # told so rather than have a deadline guessed for it.
  ISO_TIMESTAMP = /\A\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2}(:\d{2})?([.,]\d+)?(Z|[+-]\d{2}:?\d{2})?)?\z/

  def parse_time(value)
    text = value.to_s.strip
    return nil unless ISO_TIMESTAMP.match?(text)

    Time.zone.parse(text)
  rescue ArgumentError, TypeError
    nil
  end

  def find_person(name)
    needle = name.to_s.downcase.strip
    matches = User.where("LOWER(email) = :needle OR LOWER(name) = :needle", needle: needle)
    matches = User.where("LOWER(name) LIKE :like OR LOWER(email) LIKE :like", like: "%#{needle}%") if matches.empty?

    return [ nil, [ "No one matches #{name.inspect}. Try list_people." ] ] if matches.empty?
    if matches.count > 1
      return [ nil, [ "#{name.inspect} matches #{matches.count} people: #{matches.map(&:email).join(', ')}. Use an email." ] ]
    end

    [ matches.first, nil ]
  end

  def find_service(name)
    user.services.find_by("LOWER(name) = ?", name.to_s.downcase.strip)
  end

  # --- formatting --------------------------------------------------------

  def summarize(ticket, requester: false)
    parts = [
      "##{ticket.id}",
      ticket.title,
      (ticket.user.name.presence || ticket.user.email if requester),
      "#{ticket.service.name} > #{ticket.topic.name}",
      "#{ticket.priority} priority",
      ticket.status_label.downcase,
      ticket.due_label,
      ("blocked by #{ticket.outstanding_blockers.map { |blocker| "##{blocker.id}" }.join(', ')}" if ticket.blocked?),
      "#{time_ago(ticket.created_at)} old"
    ].compact

    "- #{parts.join(' · ')}"
  end

  def describe(ticket, full: false)
    lines = [
      "##{ticket.id}: #{ticket.title}",
      "Status: #{ticket.status_label.downcase} · Priority: #{ticket.priority} · #{ticket.service.name} > #{ticket.topic.name}",
      "For #{ticket.owner.display_name} · filed by #{ticket.user.display_name} #{time_ago(ticket.created_at)} ago",
      ("Due: #{ticket.due_on} — #{ticket.due_label}" if ticket.due_at.present?),
      ("Waiting on: #{list_refs(ticket.blockers)}" if ticket.blockers.any?),
      ("Blocking: #{list_refs(ticket.blocking)}" if ticket.blocking.any?),
      ("Link: #{ticket.url}" if ticket.url.present?),
      "Web: #{SlackNotifier.ticket_url(ticket)}"
    ].compact

    if full
      lines << "\n#{ticket.message}"
      lines << "\nLatest update (the requester has seen this): #{ticket.status_note}" if ticket.status_note.present?

      # Private notes are admin-only, and get_ticket is reachable by the
      # requester for their own ticket.
      events = ticket.events.oldest_first.includes(:author).select { |event| event.visible_to?(user) }

      if events.any?
        lines << "\nTimeline:"
        events.each { |event| lines << "- #{describe_event(event)}" }
      end
    end

    lines.join("\n")
  end

  def list_refs(tickets)
    tickets.map { |ticket| "#{ticket.reference} (#{ticket.status_label.downcase})" }.join(", ")
  end

  def describe_event(event)
    who = event.author.display_name
    what = case event.kind
    when "status_change" then "#{who} #{event.headline}#{": #{event.body}" if event.body.present?}"
    when "internal_note" then "#{who} (private note): #{event.body}"
    else "#{who}: #{event.body}"
    end

    files = event.files.attached? ? " [#{event.files.map { |file| file.filename }.join(', ')}]" : ""
    "#{event.created_at.to_fs(:short)} #{what}#{files}"
  end

  def time_ago(time)
    ActionController::Base.helpers.time_ago_in_words(time)
  end

  # --- JSON-RPC envelopes ------------------------------------------------

  def tool_result(text)
    { "content" => [ { "type" => "text", "text" => text.to_s } ] }
  end

  def tool_error(text)
    tool_result(text).merge("isError" => true)
  end

  def success(id, result)
    { "jsonrpc" => "2.0", "id" => id, "result" => result }
  end

  def error(id, code, message)
    { "jsonrpc" => "2.0", "id" => id, "error" => { "code" => code, "message" => message } }
  end
end
