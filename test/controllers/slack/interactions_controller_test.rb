require "test_helper"

class Slack::InteractionsControllerTest < ActionDispatch::IntegrationTest
  include SlackRequestHelpers

  test "rejects a request with a bad signature" do
    post slack_interactions_path,
         params: interaction_body(type: "shortcut"),
         headers: {
           "CONTENT_TYPE" => "application/x-www-form-urlencoded",
           "X-Slack-Request-Timestamp" => Time.now.to_i.to_s,
           "X-Slack-Signature" => "v0=not-the-right-signature"
         }

    assert_response :unauthorized
  end

  test "rejects a replayed request" do
    body = interaction_body(type: "shortcut")
    stale = 10.minutes.ago.to_i.to_s
    signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("SLACK_SIGNING_SECRET"), "v0:#{stale}:#{body}")

    post slack_interactions_path, params: body, headers: {
      "CONTENT_TYPE" => "application/x-www-form-urlencoded",
      "X-Slack-Request-Timestamp" => stale,
      "X-Slack-Signature" => signature
    }

    assert_response :unauthorized
  end

  test "the global shortcut opens a modal" do
    client = FakeSlackClient.new

    with_slack_client(client) do
      slack_post slack_interactions_path, interaction_body(
        type: "shortcut", callback_id: "create_ticket", trigger_id: "trigger-1", user: { id: "U1" }
      )
    end

    assert_response :success
    view = client.calls[:views_open].sole[:view]
    assert_equal "modal", view["type"]
    assert_equal "create_ticket", view["callback_id"]
  end

  test "the message shortcut pre-fills the modal from the message" do
    client = FakeSlackClient.new

    with_slack_client(client) do
      slack_post slack_interactions_path, interaction_body(
        type: "message_action",
        callback_id: "create_ticket_from_message",
        trigger_id: "trigger-2",
        user: { id: "U1" },
        channel: { id: "C1" },
        message: { ts: "1700000000.000100", text: "the website is on fire" }
      )
    end

    assert_response :success
    blocks = client.calls[:views_open].sole[:view]["blocks"]
    details = blocks.find { |block| block["block_id"] == "message" }
    url = blocks.find { |block| block["block_id"] == "url" }

    assert_equal "the website is on fire", details.dig("element", "initial_value")
    assert_equal "https://hackclub.slack.com/archives/C1/p1700000000", url.dig("element", "initial_value")
  end

  test "Slack's escaping and mention syntax are cleaned up before they reach the modal" do
    client = FakeSlackClient.new

    with_slack_client(client) do
      slack_post slack_interactions_path, interaction_body(
        type: "message_action",
        callback_id: "create_ticket_from_message",
        trigger_id: "trigger-6",
        user: { id: "U1" },
        channel: { id: "C1" },
        message: {
          ts: "1700000000.000100",
          text: "grants in <#C09N1P69GKZ> see <https://example.com/x?a=1&amp;b=2|the thread>"
        }
      )
    end

    prefilled = client.calls[:views_open].sole[:view]["blocks"]
                      .find { |block| block["block_id"] == "message" }
                      .dig("element", "initial_value")

    assert_equal "grants in [#hcb-grants](https://slack.com/app_redirect?channel=C09N1P69GKZ) " \
                 "see [the thread](https://example.com/x?a=1&b=2)", prefilled
  end

  test "submitting the modal creates a ticket for the Slack user" do
    client = FakeSlackClient.new

    assert_difference -> { Ticket.count }, 1 do
      with_slack_client(client) do
        slack_post slack_interactions_path, interaction_body(submission_payload)
      end
    end

    assert_response :success
    assert_equal "update", response.parsed_body["response_action"]

    ticket = Ticket.last
    assert_equal "Homepage is down", ticket.title
    assert_equal services(:website), ticket.service
    assert_equal topics(:bug), ticket.topic
    assert_equal "high", ticket.priority
    assert_equal "U999", ticket.user.slack_id
  end

  test "a failed submission returns field errors instead of creating a ticket" do
    payload = submission_payload
    payload[:view][:state][:values][:title][:title][:value] = ""

    assert_no_difference -> { Ticket.count } do
      with_slack_client do
        slack_post slack_interactions_path, interaction_body(payload)
      end
    end

    assert_response :success
    assert_equal "errors", response.parsed_body["response_action"]
    assert response.parsed_body["errors"]["title"].present?
  end

  test "an admin picking a status from the Home tab gets the note modal" do
    ticket = tickets(:website_bug)
    client = FakeSlackClient.new

    with_slack_client(client) do
      slack_post slack_interactions_path, interaction_body(
        type: "block_actions",
        trigger_id: "trigger-3",
        user: { id: users(:amber).slack_id },
        actions: [ { action_id: "set_status", selected_option: { value: "#{ticket.id}:done" } } ]
      )
    end

    assert_response :success
    view = client.calls[:views_open].sole[:view]
    assert_equal "update_ticket", view["callback_id"]
    assert_equal "#{ticket.id}:done", view["private_metadata"]
    # Nothing changes until the modal is submitted.
    refute ticket.reload.done?
  end

  test "a non-admin picking a status gets no modal" do
    ticket = tickets(:website_bug)
    client = FakeSlackClient.new

    with_slack_client(client) do
      slack_post slack_interactions_path, interaction_body(
        type: "block_actions",
        trigger_id: "trigger-4",
        user: { id: "U-not-an-admin" },
        actions: [ { action_id: "set_status", selected_option: { value: "#{ticket.id}:done" } } ]
      )
    end

    assert_response :success
    assert_empty client.calls[:views_open]
    refute ticket.reload.done?
  end

  test "submitting the update modal applies the status and note" do
    ticket = tickets(:website_bug)

    with_slack_client do
      slack_post slack_interactions_path, interaction_body(
        type: "view_submission",
        user: { id: users(:amber).slack_id },
        view: {
          callback_id: "update_ticket",
          private_metadata: "#{ticket.id}:done",
          state: { values: { note: { note: { value: "Fixed in this morning's deploy." } } } }
        }
      )
    end

    assert_response :success
    ticket.reload
    assert ticket.done?
    assert_equal "Fixed in this morning's deploy.", ticket.status_note
  end

  test "the update modal offers every status, including wont do" do
    ticket = tickets(:website_bug)
    client = FakeSlackClient.new

    with_slack_client(client) do
      slack_post slack_interactions_path, interaction_body(
        type: "block_actions", trigger_id: "trigger-5", user: { id: users(:amber).slack_id },
        actions: [ { action_id: "set_status", selected_option: { value: "#{ticket.id}:wont_do" } } ]
      )
    end

    view = client.calls[:views_open].sole[:view]
    assert_match "Won't do", view.to_json
    assert_equal "#{ticket.id}:wont_do", view["private_metadata"]
  end

  test "the update modal can add an internal note alongside the status" do
    ticket = tickets(:website_bug)

    with_slack_client do
      slack_post slack_interactions_path, interaction_body(
        type: "view_submission",
        user: { id: users(:amber).slack_id },
        view: {
          callback_id: "update_ticket",
          private_metadata: "#{ticket.id}:wont_do",
          state: { values: {
            note: { note: { value: "Not going to get to this, sorry." } },
            internal_note: { internal_note: { value: "Duplicate of the other request." } }
          } }
        }
      )
    end

    ticket.reload
    assert ticket.wont_do?
    assert_equal "Not going to get to this, sorry.", ticket.status_note
    assert_equal "Duplicate of the other request.", ticket.events.internal_note.sole.body
    assert_equal users(:amber), ticket.events.internal_note.sole.author
  end

  test "an unknown status from Slack changes nothing" do
    ticket = tickets(:website_bug)

    with_slack_client do
      slack_post slack_interactions_path, interaction_body(
        type: "view_submission",
        user: { id: users(:amber).slack_id },
        view: { callback_id: "update_ticket", private_metadata: "#{ticket.id}:nonsense", state: { values: {} } }
      )
    end

    assert_response :success
    assert_equal "open", ticket.reload.status
  end

  test "a non-admin submitting the update modal changes nothing" do
    ticket = tickets(:website_bug)

    with_slack_client do
      slack_post slack_interactions_path, interaction_body(
        type: "view_submission",
        user: { id: "U-still-not-an-admin" },
        view: {
          callback_id: "update_ticket",
          private_metadata: "#{ticket.id}:done",
          state: { values: { note: { note: { value: "sneaky" } } } }
        }
      )
    end

    assert_response :success
    refute ticket.reload.done?
  end

  test "a deadline picked in the modal lands on the ticket" do
    payload = submission_payload
    payload[:view][:state][:values][:due] = { due: { selected_date_time: 1_790_000_000 } }

    with_slack_client do
      slack_post slack_interactions_path, interaction_body(payload)
    end

    assert_equal Time.zone.at(1_790_000_000), Ticket.last.due_at
  end

  test "an untouched deadline picker leaves the ticket without one" do
    with_slack_client do
      slack_post slack_interactions_path, interaction_body(submission_payload)
    end

    assert_nil Ticket.last.due_at
  end

  test "the update modal can set a deadline and link a blocker" do
    ticket = tickets(:website_bug)
    blocker = users(:requester).tickets.create!(
      title: "The thing it waits on", message: "…", service: services(:website), topic: topics(:bug)
    )

    with_slack_client do
      slack_post slack_interactions_path, interaction_body(
        type: "view_submission",
        user: { id: users(:amber).slack_id },
        view: {
          callback_id: "update_ticket",
          private_metadata: "#{ticket.id}:in_progress",
          state: { values: {
            due: { due: { selected_date_time: 1_790_000_000 } },
            blocker: { blocker: { selected_option: { value: blocker.id.to_s } } }
          } }
        }
      )
    end

    ticket.reload
    assert_equal Time.zone.at(1_790_000_000), ticket.due_at
    assert_equal [ blocker ], ticket.blockers
    assert ticket.blocked?
  end

  test "the update modal can clear a deadline" do
    ticket = tickets(:website_bug)
    ticket.update!(due_at: 1.day.from_now)

    with_slack_client do
      slack_post slack_interactions_path, interaction_body(
        type: "view_submission",
        user: { id: users(:amber).slack_id },
        view: {
          callback_id: "update_ticket",
          private_metadata: "#{ticket.id}:in_progress",
          state: { values: {
            due: { due: { selected_date_time: ticket.due_at.to_i } },
            clear_due: { clear_due: { selected_options: [ { value: "clear" } ] } }
          } }
        }
      )
    end

    assert_nil ticket.reload.due_at
  end

  test "an untouched deadline picker in the update modal keeps the existing one" do
    ticket = tickets(:website_bug)
    ticket.update!(due_at: 1.day.from_now)
    was = ticket.due_at

    with_slack_client do
      slack_post slack_interactions_path, interaction_body(
        type: "view_submission",
        user: { id: users(:amber).slack_id },
        view: {
          callback_id: "update_ticket",
          private_metadata: "#{ticket.id}:done",
          state: { values: {} }
        }
      )
    end

    assert_equal was.to_i, ticket.reload.due_at.to_i
  end

  test "an enabled person can triage their own ticket from Slack" do
    owner = another_owner
    owner.update!(slack_id: "U000BO")
    ticket = ticket_for(owner, requester: users(:requester))

    with_slack_client do
      slack_post slack_interactions_path, interaction_body(
        type: "view_submission",
        user: { id: "U000BO" },
        view: {
          callback_id: "update_ticket",
          private_metadata: "#{ticket.id}:done",
          state: { values: { note: { note: { value: "Sorted." } } } }
        }
      )
    end

    assert ticket.reload.done?
  end

  test "an enabled person can't triage somebody else's" do
    owner = another_owner
    owner.update!(slack_id: "U000BO")
    ticket = tickets(:website_bug)

    with_slack_client do
      slack_post slack_interactions_path, interaction_body(
        type: "view_submission",
        user: { id: "U000BO" },
        view: {
          callback_id: "update_ticket",
          private_metadata: "#{ticket.id}:done",
          state: { values: {} }
        }
      )
    end

    refute ticket.reload.done?
  end

  private

  def submission_payload
    {
      type: "view_submission",
      user: { id: "U999" },
      view: {
        callback_id: "create_ticket",
        state: {
          values: {
            title: { title: { value: "Homepage is down" } },
            topic: { topic: { selected_option: { value: "#{services(:website).id}:#{topics(:bug).id}" } } },
            priority: { priority: { selected_option: { value: "high" } } },
            url: { url: { value: "https://hackclub.com" } },
            message: { message: { value: "It 500s on load." } }
          }
        }
      }
    }
  end
end
