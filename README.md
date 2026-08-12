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

## Roadmap

- [x] **M0** Scaffold: Rails 8, Postgres, CI (RuboCop + tests + Brakeman), Docker dev, Kamal stub
- [ ] **M1** Ingest — `POST /in/:token` persists an event and returns `202`
- [ ] **M2** Deliver — a job forwards each event to its destination, recording every attempt
- [ ] **M3** Retries — exponential backoff + jitter, max attempts, dead-letter
- [ ] **M4** Inspector UI — a Hotwire dashboard; attempts stream in live
- [ ] **M5** Replay — re-deliver an event from the UI and API
- [ ] **M6** Signatures — verify inbound provider HMAC, sign outbound
- [ ] **M7** Multi-tenant accounts + API keys
- [ ] **M8** Idempotency keys + rate limiting
- [ ] **M9** Observability — per-destination success rate, latency, retries
- [ ] **M10** Deploy (Kamal) + demo + `v0.1.0`
