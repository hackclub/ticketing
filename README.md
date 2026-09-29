# Tickets

A small internal ticket tracker: anyone signs in with Hack Club Auth, files a
ticket (service, topic, priority, a markdown message), and gets emailed when
its status changes. The admin dashboard (anyone listed in `ADMIN_EMAILS`)
shows every open/in-progress ticket, sorted with VIP requesters and higher
priority first.

## Stack

Rails 8.1, PostgreSQL, Tailwind (via `tailwindcss-rails`, no Node needed),
Solid Queue for background email delivery, OmniAuth + Hack Club Auth (OIDC)
for sign-in.

## Setup

```
bin/setup        # bundle install, db:prepare
cp .env.example .env
bin/dev          # Rails server + Tailwind watcher
```

Visit `http://localhost:3000`. With no `HACKCLUB_AUTH_CLIENT_ID` set, sign-in
uses a local-only `:developer` strategy (type any name/email) instead of the
real Hack Club Auth flow — handy for developing without registering an app
first. Notification emails pop open in your browser via `letter_opener`
instead of requiring real SMTP credentials.

## Going live with real Hack Club Auth

1. Register an app at https://auth.hackclub.com/developer/apps.
2. Set its redirect URI to `https://<your-host>/auth/hackclub/callback`.
3. Set `HACKCLUB_AUTH_CLIENT_ID`, `HACKCLUB_AUTH_CLIENT_SECRET`, and
   `HACKCLUB_AUTH_REDIRECT_URI` (see `.env.example`).

Once `HACKCLUB_AUTH_CLIENT_ID` is present, the app always uses the real OIDC
strategy in every environment except test.

## Configuring services & topics

Services and topics (each topic belongs to one service) are managed from
`/admin/services` and `/admin/topics` by anyone in `ADMIN_EMAILS` — no code
changes needed to add or retire a category. `db/seeds.rb` creates a starter
set.

## MCP

The app is also an MCP server, so tickets can be filed and triaged from Claude
(or any MCP client). Generate a token at `/settings`, then:

```
claude mcp add --transport http tickets https://amber.hackclub.com/mcp \
  --header "Authorization: Bearer YOUR_TOKEN"
```

Tools are scoped to whoever the token belongs to. Everyone gets
`list_services`, `create_ticket`, `list_my_tickets` and `get_ticket`; admins
also get `my_queue`, `update_ticket_status`, and taxonomy management
(`create_service`, `update_service`, `create_topic`, `update_topic`).
Non-admins don't just get refused on the admin tools — the tools aren't listed
for them at all.

Services and topics can be retired (`active: false`) but not deleted over MCP;
deletion stays on the web, where it's a deliberate click behind a confirm.

Tokens are stored as SHA-256 digests and displayed once at generation.

## Slack

`slack-app-manifest.yml` is the source of truth for the **Ambot** Slack app
(`A0BQECK593K`). Update it with:

```
ruby -ryaml -rjson -rnet/http -ruri -e 'manifest = YAML.load_file("slack-app-manifest.yml"); \
  puts Net::HTTP.post_form(URI("https://slack.com/api/apps.manifest.update"), \
  "token" => ENV["SLACK_CONFIG_TOKEN"], "app_id" => "A0BQECK593K", "manifest" => JSON.generate(manifest)).body'
```

with a config token from https://api.slack.com/authentication/config-tokens.
Changing the Events request URL makes Slack re-verify it, so the app has to be
deployed and `SLACK_SIGNING_SECRET` set before that update will be accepted.

## Email

Development uses `letter_opener`. Production sends via SMTP — set
`SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_DOMAIN`, `SMTP_USER_NAME`, `SMTP_PASSWORD`.

## Deployment

Orchard project **Tickets**, deployment `web`, auto-deploying from `main`.
Two settings there aren't in this repo and matter:

- **CPU limit 1000m.** The 250m it started on throttled everything about 4x —
  a `SELECT 1` took 9.6ms rather than 1.3ms, because the starvation showed up
  as what looked like database latency.
- **A 5Gi volume at `/rails/storage`** for Active Storage attachments, which
  forces the `recreate` deploy strategy (a volume like that attaches to one
  pod at a time) and so a few seconds of downtime per deploy. Kubernetes
  mounts it root-owned, which is why `bin/docker-entrypoint` starts as root,
  takes ownership of that one directory and drops back to the `rails` user.

## Tests

```
bin/rails test
```
