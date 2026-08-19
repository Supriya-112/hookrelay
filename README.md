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

Accounts arrive in M7. Until then, a deployment that is reachable can put a
password in front of the inspector — set both and every inspector page asks for
it, while the ingest endpoint stays open:

```bash
HOOKRELAY_INSPECTOR_USER=you HOOKRELAY_INSPECTOR_PASSWORD=secret
```

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

Secrets are held in plain columns for now. Encrypting them at rest belongs with
the account work in M7, since it needs an encryption key wherever the tests run
as well as in the deploy.

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
endpoints sit behind the inspector password when one is set.

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

## Roadmap

- [x] **M0** Scaffold: Rails 8, Postgres, CI (RuboCop + tests + Brakeman), Docker dev, Kamal stub
- [x] **M1** Ingest — `POST /in/:token` persists an event and returns `202`
- [x] **M2** Deliver — a job forwards each event to its destination, recording every attempt
- [x] **M3** Retries — exponential backoff + jitter, max attempts, dead-letter
- [x] **M4** Inspector UI — a Hotwire dashboard; attempts stream in live
- [x] **M5** Replay — re-deliver an event from the UI and API
- [x] **M6** Signatures — verify inbound provider HMAC, sign outbound
- [ ] **M7** Multi-tenant accounts + API keys
- [ ] **M8** Idempotency keys + rate limiting
- [ ] **M9** Observability — per-destination success rate, latency, retries
- [ ] **M10** Deploy (Kamal) + demo + `v0.1.0`
