# Model Context Protocol endpoint (Streamable HTTP transport). Authenticated
# with a personal API token rather than the browser session, so it doesn't
# inherit ApplicationController's login redirect.
class McpController < ActionController::Base
  skip_forgery_protection

  rate_limit to: 120, within: 1.minute, by: -> { request.authorization.to_s }, only: :create

  before_action :authenticate_api_token!

  def create
    payload = JSON.parse(request.raw_post)
    Current.user = @current_user
    server = McpServer.new(@current_user)

    if payload.is_a?(Array)
      responses = payload.filter_map { |message| server.handle(message) }
      responses.any? ? render(json: responses) : head(:accepted)
    else
      response_body = server.handle(payload)
      response_body ? render(json: response_body) : head(:accepted)
    end
  rescue JSON::ParserError
    render json: { "jsonrpc" => "2.0", "id" => nil,
                   "error" => { "code" => McpServer::PARSE_ERROR, "message" => "Invalid JSON" } },
           status: :bad_request
  end

  # The server never initiates messages, so there's no stream to open.
  def unsupported
    head :method_not_allowed
  end

  private

  # Two ways in: a personal API token (simplest for CLI clients that can send a
  # header) or an OAuth access token (for clients that can only do OAuth).
  def authenticate_api_token!
    token = request.authorization.to_s[/\ABearer (.+)\z/i, 1]
    @current_user = User.authenticate_api_token(token) || OauthToken.authenticate(token)&.user

    return if @current_user

    # RFC 9728: point the client at discovery so it can start the OAuth dance.
    response.set_header(
      "WWW-Authenticate",
      %(Bearer realm="tickets", resource_metadata="#{root_url.chomp('/')}/.well-known/oauth-protected-resource")
    )
    render json: { "jsonrpc" => "2.0", "id" => nil,
                   "error" => { "code" => McpServer::INVALID_REQUEST, "message" => "Invalid or missing API token" } },
           status: :unauthorized
  end
end
