module ApplicationHelper
  # Links that leave the app open in a new tab; links back into it don't, so
  # following one doesn't strand you with two tabs on the same site.
  # noopener/noreferrer because the destination is whatever someone typed.
  LINK_ATTRIBUTES = { target: "_blank", rel: "noopener noreferrer" }.freeze

  def self.app_host
    ENV.fetch("APP_HOST", "localhost:3000").split(":").first.downcase
  end

  def self.external_url?(url)
    host = URI.parse(url.to_s).host
    host.present? && host.downcase != app_host
  rescue URI::InvalidURIError
    false
  end

  # Redcarpet's link_attributes would put target="_blank" on every link, so
  # the decision is made per link here instead.
  class ExternalLinkRenderer < Redcarpet::Render::HTML
    def link(url, title, content)
      # safe_links_only hands back a blank url for a link it refused
      # (javascript: and friends) — render the text, not an empty anchor.
      return content if url.blank?

      attributes = %(href="#{ERB::Util.html_escape(url)}")
      attributes += %( title="#{ERB::Util.html_escape(title)}") if title.present?
      attributes += %( class="slack-mention") if SlackText.mention_url?(url)
      attributes += %( target="_blank" rel="noopener noreferrer") if ApplicationHelper.external_url?(url)

      "<a #{attributes}>#{content}</a>"
    end

    def autolink(url, link_type)
      return super if link_type == :email

      link(url, nil, ERB::Util.html_escape(url))
    end
  end

  MARKDOWN_RENDERER = Redcarpet::Markdown.new(
    ExternalLinkRenderer.new(filter_html: true, safe_links_only: true, hard_wrap: true),
    autolink: true,
    fenced_code_blocks: true,
    tables: true,
    no_intra_emphasis: true
  )

  MARKDOWN_TAGS = %w[p br strong em a ul ol li h1 h2 h3 h4 blockquote code pre table thead tbody tr th td hr del].freeze
  # target, rel and class have to survive sanitising, or the renderer's work is
  # undone. Nothing a person writes can reach these: filter_html drops raw HTML
  # before this runs, so every attribute here was written by the renderer.
  MARKDOWN_ATTRIBUTES = %w[href target rel class].freeze

  # A Slack permalink is ~200 unreadable characters, so it gets a label
  # instead. Everything else shows the URL, which is the useful part.
  def ticket_link_label(url)
    return url unless SlackText.permalink?(url)

    where = SlackText.permalink_channel(url, client: SlackNotifier.reader)
    where.in?([ nil, "Slack" ]) ? "View message in Slack" : "View message in #{where}"
  end

  def external_link_attributes(url)
    ApplicationHelper.external_url?(url) ? LINK_ATTRIBUTES : {}
  end

  def markdown(text)
    sanitize(MARKDOWN_RENDERER.render(text.to_s), tags: MARKDOWN_TAGS, attributes: MARKDOWN_ATTRIBUTES)
  end

  # Returns nil when the user has no Slack ID yet (no external image service
  # is called in that case) — pair with #avatar_initial for a local fallback.
  def avatar_url(user)
    "https://cachet.hackclub.com/users/#{user.slack_id}/r" if user&.slack_id.present?
  end

  # Opens a Slack DM with this person in whichever Slack client they use.
  def slack_dm_url(user)
    return if user&.slack_id.blank?

    url = "https://slack.com/app_redirect?channel=#{user.slack_id}"
    team = ENV["SLACK_TEAM_ID"].presence
    team ? "#{url}&team=#{team}" : url
  end

  def avatar_initial(user)
    (user&.name.presence || user&.email.to_s).to_s.first.to_s.upcase.presence || "?"
  end

  # Every avatar is a request to cachet, so rows below the fold wait until
  # they're actually scrolled to.
  def avatar_tag(user, css_class: "size-8 rounded-full")
    if (url = avatar_url(user))
      image_tag(url, alt: user.name.to_s, class: css_class, loading: "lazy", decoding: "async")
    else
      content_tag(:div, avatar_initial(user), class: "#{css_class} bg-red-500 text-white flex items-center justify-center font-semibold shrink-0")
    end
  end

  PRIORITY_CLASSES = {
    "low" => "bg-gray-100 text-gray-700",
    "medium" => "bg-blue-100 text-blue-700",
    "high" => "bg-orange-100 text-orange-700",
    "urgent" => "bg-red-100 text-red-700"
  }.freeze

  STATUS_CLASSES = {
    "open" => "bg-yellow-100 text-yellow-800",
    "in_progress" => "bg-blue-100 text-blue-800",
    "done" => "bg-green-100 text-green-800",
    "wont_do" => "bg-gray-200 text-gray-600"
  }.freeze

  # Ticket#url is validated to be http(s) already, but re-checking at render
  # time keeps the view safe even if that ever changes.
  def safe_http_url(url)
    uri = URI.parse(url.to_s)
    url if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end

  # Shared box styling for text/select/textarea inputs. Tailwind's `border-*`
  # color utilities need a `border` width utility alongside them or nothing
  # renders — easy to drop, so it's centralized here instead of repeated.
  def input_classes(extra = nil)
    "block w-full rounded-md border border-gray-300 bg-white px-3 py-2 shadow-sm " \
    "focus:border-red-500 focus:ring-1 focus:ring-red-500 focus:outline-none #{extra}".strip
  end

  def priority_badge_classes(priority)
    PRIORITY_CLASSES.fetch(priority.to_s, "bg-gray-100 text-gray-700")
  end

  def status_badge_classes(status)
    STATUS_CLASSES.fetch(status.to_s, "bg-gray-100 text-gray-700")
  end

  # Red once a deadline has passed, amber as it approaches, quiet otherwise —
  # so a glance down the queue shows what's actually burning.
  def due_badge_classes(ticket)
    return "bg-red-100 text-red-700" if ticket.overdue?
    return "bg-amber-100 text-amber-800" if ticket.due_soon?

    "bg-gray-100 text-gray-600"
  end
end
