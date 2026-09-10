# Hookrelay

[![CI](https://github.com/Supriya-112/hookrelay/actions/workflows/ci.yml/badge.svg)](https://github.com/Supriya-112/hookrelay/actions/workflows/ci.yml)

A self-hostable **webhook gateway**. Point any provider at a durable Hookrelay
URL and it queues each event, delivers it to your endpoints with **retries and
backoff**, **dead-letters** what can't be delivered, lets you **replay**, and
shows a **live inspector** of every request and delivery attempt.

> **Status: early development.** Building in the open, one milestone at a time —
> see the [roadmap](#roadmap).

## Why

Webhooks are how services talk to each other, but receiving them reliably is
its own project: you need durable storage so nothing is lost, retries with
backoff for flaky endpoints, a dead-letter path, a way to replay, and visibility
into what actually happened. Hookrelay is a small, readable take on that — a
single self-hostable app you run in front of your endpoints.

## Stack

Rails 8 · Hotwire (Turbo/Stimulus) · Solid Queue / Cache / Cable (no Redis) ·
PostgreSQL · deployed with Kamal.

## Development

Everything runs in Docker — no Ruby or Postgres needed on your machine:

```bash
docker compose up                          # boot the app at http://localhost:3000
docker compose run --rm web bin/rails test # run the test suite
docker compose run --rm web bin/rails c    # a console
```

The app connects to the bundled Postgres over `DATABASE_URL`; gems and DB data
persist in named volumes.

### Try the ingest endpoint

```bash
docker compose up -d
# create a source and copy its token
docker compose exec web bin/rails runner 'puts Source.create!(name: "demo").token'
# POST a webhook to it
curl -i -X POST http://localhost:3000/in/<token> \
  -H 'Content-Type: application/json' -d '{"hello":"world"}'
# => HTTP/1.1 202 Accepted
```

The event is stored with its method, headers, and body — bytes exactly as they
arrived, so gzipped and protobuf payloads survive as well as JSON. Give the
source a destination (`source.destinations.create!(url: "https://…")` in
`rails c`) and each event is delivered to it, recording every attempt.

## The inspector

Open <http://localhost:3000> for the dashboard: sources and their ingest URLs,
then each source's events, then everything about one event — its headers (with
credentials masked), its body (JSON pretty-printed, non-text payloads shown
safely), and every delivery with each attempt's status, duration and response.
Events and attempts arrive over Turbo Streams, so a page left open fills in as
webhooks land.

## Accounts

Everything belongs to an account: its sources, and through them the events and
deliveries that follow. One account can't see another's — asking for someone
else's event gets the same answer as asking for one that never existed.

The first visit to a new install offers a setup form, which creates the account
and its first user; after that the form is closed, and anyone else who needs
access is added from a console:

```ruby
Account.first.users.create!(email_address: "them@example.com", password: "…")
```

Ingest is the one thing outside all this. A provider has no account and nothing
to sign in with, so `POST /in/:token` stays open — the token identifies the
source and a signature vouches for the request.

### API keys

The replay endpoints also take a key, so scripts don't need a browser session.
Create one on the API keys page — it's shown once, and only its digest is stored —
then send it as a bearer token:

```bash
curl -X POST -H 'Accept: application/json' \
  -H "Authorization: Bearer $HOOKRELAY_API_KEY" \
  https://hookrelay.example.com/events/13/replay
```

A key only reaches its own account's events, and its last use is recorded so a
forgotten one can be spotted and revoked.

## Retries from the provider, and limits

Providers retry, and a retry is not a new event. When a request names its delivery
— `Idempotency-Key`, `Webhook-Id`, `X-Github-Delivery`, `X-Shopify-Webhook-Id` or
`X-Svix-Id` — that name is stored with the event, unique per source. A repeat gets
the first event back and is not delivered again:

```json
{ "event_id": 41, "duplicate": true }
```

A provider that names nothing still gets an event per request; there's nothing to
match on, and inventing a key from the body would collide on two genuinely
identical webhooks.

Ingest also refuses what it shouldn't accept:

| | default | override |
|---|---|---|
| body size | 1 MiB → `413` | `HOOKRELAY_MAX_BODY_BYTES` |
| requests per source | 300 / minute → `429` with `Retry-After` | `HOOKRELAY_SOURCE_RATE_LIMIT`, `HOOKRELAY_RATE_LIMIT_PERIOD` |

The rate limit is per source, so one provider having a bad day can't crowd out
the others. It is deliberately not also keyed by address — an address limit
belongs at the edge, where it sees the whole site and can't be sidestepped by
rotating the token in the URL. The body cap is a backstop for the same reason:
by the time Rails sees the request the body has already been read off the socket.

## Signatures

**Inbound.** Tell a source how its provider signs and give it the secret that
provider was issued, and every request is checked before anything is stored:

```ruby
Source.create!(name: "GitHub", signature_scheme: "github",
               signing_secret: ENV["GITHUB_WEBHOOK_SECRET"])
```

`github` expects `X-Hub-Signature-256`, `stripe` expects `Stripe-Signature` —
whose timestamp has to be within five minutes, so an intercepted request can't be
sent again later. Whatever fails the check gets `401` and is not recorded: it
can't be attributed to the provider, and storing it would let anyone who learns
the URL fill the inspector. A source with no scheme accepts what reaches its URL.

**Outbound.** Every destination gets a secret of its own, and each delivery
carries the HMAC-SHA256 of `"<timestamp>.<body>"`:

```
X-Hookrelay-Signature: t=1755600000,v1=4fe215412bcaaace…
```

Checking it at the receiving end is a few lines — the secret is shown on the
source's page in the inspector:

```ruby
timestamp, signature = request.headers["X-Hookrelay-Signature"].split(",").map { |part| part.split("=", 2).last }
expected = OpenSSL::HMAC.hexdigest("SHA256", ENV["HOOKRELAY_SECRET"], "#{timestamp}.#{request.raw_post}")

head :unauthorized unless (Time.now.to_i - timestamp.to_i).abs < 300 &&
  ActiveSupport::SecurityUtils.secure_compare(signature, expected)
```

Both kinds of secret are encrypted at rest, so a database dump doesn't hand over
the means to forge webhooks. The keys come from the environment —
`AR_ENCRYPTION_PRIMARY_KEY`, `AR_ENCRYPTION_DETERMINISTIC_KEY` and
`AR_ENCRYPTION_KEY_DERIVATION_SALT`. `docker-compose.yml` and the CI workflow set
throwaway ones, which is why neither development nor the test suite needs any
setup; a deployment makes its own with `bin/rails db:encryption:init` and keeps
them with the rest of its secrets. Losing them means losing every stored secret,
and running outside Docker means setting them yourself.

## Replay

Send a received event again — all of it, or one destination's delivery — from the
inspector's buttons or over HTTP:

```bash
curl -X POST -H 'Accept: application/json' http://localhost:3000/events/13/replay
# => 202 {"event_id":13,"destinations":2,"deliveries_reset":2}

curl -X POST -H 'Accept: application/json' http://localhost:3000/deliveries/8/replay
# => 202 {"delivery_id":8,"status":"pending"}
```

A replay reuses the delivery rather than copying it: the attempts already on it
stay as history, while the retry budget starts over — so a dead-lettered delivery
gets its five tries again, and the inspector shows both runs. A delivery a worker
is currently holding is left alone (`409`), since it is already on its way.
Replaying an event also covers destinations added since it arrived. Both
endpoints need either a signed-in session or an API key.

## How delivery behaves

- **One POST per delivery.** A worker claims a delivery before sending it, so a
  duplicated or overlapping job can't deliver the same event twice.
- **Retries with backoff.** A failed attempt is retried up to five times, waiting
  5s, 10s, 20s … capped at an hour, with jitter so a burst of failures to one
  destination doesn't retry in lockstep. After that the delivery is dead.
- **Nothing gets stranded.** A worker that dies mid-delivery, or a retry lost with
  its queue, is picked up by a sweep that runs every five minutes; the lost
  attempt is recorded, so it still counts against the retry budget.
- **Private addresses are refused.** Destinations are user-supplied, so
  deliveries to loopback, link-local (including the cloud metadata endpoint) and
  private ranges are rejected and logged rather than sent. Local development
  needs the opposite, so `docker compose` sets
  `HOOKRELAY_ALLOW_PRIVATE_DESTINATIONS=true` and can deliver to sinks on your
  machine.

## Destination health

Each source page shows, per destination, how it's actually doing:

- **Success rate** — of the deliveries that have concluded (succeeded or
  dead-lettered), the share that succeeded. One still pending or waiting on a
  retry isn't counted either way until it's settled.
- **Latency** — the average response time of successful attempts only. A
  failed attempt's duration doesn't reflect how fast the destination normally
  responds, so it isn't counted.
- **Retries** — attempts beyond each delivery's first. A destination that
  needs a retry now and then is different from one that never gets there
  without one.

All three are all-time, computed from the attempts already on record — nothing
extra to configure or store. A destination shows `—` where nothing has
concluded yet, rather than a rate or latency with nothing behind it.

## Deploy

`config/deploy.yml` is configured for this app — a self-hosted Postgres
accessory, `ghcr.io` as the registry, every secret the app actually needs — but
it isn't pointed at a real server yet. `203.0.113.1` (reserved for
documentation, RFC 5737) stands in for one in both places it's used.

To actually deploy:

1. Get a server with Docker installed and point `&server` in `config/deploy.yml`
   at its address.
2. Export these before running any `bin/kamal` command — generate the
   `AR_ENCRYPTION_*` ones with `bin/rails db:encryption:init`, and don't reuse
   the `hookrelay-dev-*` values `docker-compose.yml` uses for local work:
   `KAMAL_REGISTRY_PASSWORD` (a GitHub PAT with `write:packages`),
   `AR_ENCRYPTION_PRIMARY_KEY`, `AR_ENCRYPTION_DETERMINISTIC_KEY`,
   `AR_ENCRYPTION_KEY_DERIVATION_SALT`, `HOOKRELAY_DATABASE_PASSWORD`.
3. `bin/kamal setup` — builds the image, starts the db accessory, boots the
   app. `bin/docker-entrypoint` runs `db:prepare` on every boot, which creates
   the primary/cache/queue/cable databases on first run.
4. Once there's a domain, uncomment `proxy:` in `config/deploy.yml` for
   Let's Encrypt SSL, and turn on `config.assume_ssl`/`config.force_ssl` in
   `config/environments/production.rb`.

No live demo yet — this is what a deploy needs, not a deploy that's happened.

## Roadmap

- [x] **M0** Scaffold: Rails 8, Postgres, CI (RuboCop + tests + Brakeman), Docker dev, Kamal stub
- [x] **M1** Ingest — `POST /in/:token` persists an event and returns `202`
- [x] **M2** Deliver — a job forwards each event to its destination, recording every attempt
- [x] **M3** Retries — exponential backoff + jitter, max attempts, dead-letter
- [x] **M4** Inspector UI — a Hotwire dashboard; attempts stream in live
- [x] **M5** Replay — re-deliver an event from the UI and API
- [x] **M6** Signatures — verify inbound provider HMAC, sign outbound
- [x] **M7** Multi-tenant accounts + API keys
- [x] **M8** Idempotency keys + rate limiting
- [x] **M9** Observability — per-destination success rate, latency, retries
- [ ] **M10** Deploy (Kamal) + demo + `v0.1.0`
