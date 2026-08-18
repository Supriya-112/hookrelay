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
- [ ] **M5** Replay — re-deliver an event from the UI and API
- [ ] **M6** Signatures — verify inbound provider HMAC, sign outbound
- [ ] **M7** Multi-tenant accounts + API keys
- [ ] **M8** Idempotency keys + rate limiting
- [ ] **M9** Observability — per-destination success rate, latency, retries
- [ ] **M10** Deploy (Kamal) + demo + `v0.1.0`
