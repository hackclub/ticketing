require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "slack_dm_url opens a DM with someone who has a Slack ID" do
    url = slack_dm_url(users(:amber))

    assert_includes url, "https://slack.com/app_redirect?channel=U000AMBER"
  end

  test "slack_dm_url includes the team when one is configured" do
    with_env("SLACK_TEAM_ID" => "T0266FRGM") do
      assert_includes slack_dm_url(users(:amber)), "team=T0266FRGM"
    end
  end

  test "slack_dm_url is nil for someone who has never used Slack here" do
    assert_nil slack_dm_url(users(:requester))
    assert_nil slack_dm_url(nil)
  end

  test "links that leave the app open in a new tab" do
    html = markdown("See [the docs](https://example.com/docs)")

    assert_includes html, %(target="_blank")
    assert_includes html, %(rel="noopener noreferrer")
  end

  test "links back into the app stay in the tab" do
    with_env("APP_HOST" => "amber.hackclub.com") do
      html = markdown("see [ticket 3](https://amber.hackclub.com/tickets/3)")

      assert_includes html, %(href="https://amber.hackclub.com/tickets/3")
      assert_no_match(/target=/, html)
    end
  end

  test "external_link_attributes decides per host" do
    with_env("APP_HOST" => "amber.hackclub.com") do
      assert_equal ApplicationHelper::LINK_ATTRIBUTES, external_link_attributes("https://example.com")
      assert_empty external_link_attributes("https://amber.hackclub.com/tickets/3")
      assert_empty external_link_attributes("/tickets/3")
      assert_empty external_link_attributes(nil)
    end
  end

  test "bare urls are autolinked and open in a new tab too" do
    html = markdown("it's at https://example.com/thing")

    assert_includes html, %(href="https://example.com/thing")
    assert_includes html, %(target="_blank")
  end

  test "markdown never turns a javascript url into a link" do
    html = markdown("[click me](javascript:alert)")

    # Redcarpet leaves it as plain text rather than linking it, so what
    # matters is that no anchor carries the scheme.
    assert_no_match(/<a[^>]*javascript/i, html)
    assert_no_match(/<a /, html)
  end

  test "markdown still strips raw html" do
    html = markdown("<script>alert(1)</script><b>hi</b>")

    assert_no_match(/<script/, html)
  end

  test "an email address in a message becomes a mailto link" do
    html = markdown("email me at amber@hackclub.com please")

    assert_match %(<a href="mailto:amber@hackclub.com">amber@hackclub.com</a>), html
  end

  # The email case used to call up to a method Redcarpet only implements in C.
  # That raised mid-render, which both 500'd the ticket and left Redcarpet's
  # buffers unbalanced — the next render aborted the whole process.
  test "a message with an email in it renders, twice, without taking the process with it" do
    2.times do
      assert_match "mailto:", markdown("write to someone@example.com about it")
    end

    assert_match "example.com/x", markdown("and [a link](https://example.com/x) after")
  end

  test "an email and a link in the same message both come out right" do
    html = markdown("mail amber@hackclub.com or see https://example.com/x")

    assert_match %(href="mailto:amber@hackclub.com"), html
    assert_match %(href="https://example.com/x"), html
    # A mailto isn't somewhere to send a new tab.
    assert_no_match(/mailto:[^"]*" target/, html)
  end

  test "a Slack mention is marked so it can be styled like one" do
    html = markdown("Hey [@Amber](#{SlackText.deep_link('U054VC2KM9P')}), thoughts?")

    assert_match(/<a[^>]*class="slack-mention"[^>]*>@Amber<\/a>/, html)
  end

  test "an ordinary link is left as an ordinary link" do
    html = markdown("see [the thread](https://example.com/x)")

    assert_no_match(/slack-mention/, html)
  end

  test "a Slack permalink is a link, not a mention" do
    html = markdown("[a message](https://hackclub.slack.com/archives/C1/p1700000000)")

    assert_no_match(/slack-mention/, html)
  end

  test "nobody can smuggle a class of their own through markdown" do
    html = markdown(%(<a href="https://example.com" class="fixed inset-0">hi</a>))

    assert_no_match(/class=/, html)
  end

  private

  def with_env(values)
    original = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end
end
