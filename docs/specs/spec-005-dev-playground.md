---
status: shipped
date: 2026-07-10
depends_on: [spec-004, adr-002, adr-006]
---

# Spec 005: In-repo dev playground

A runnable Phoenix app inside this repo for manually exercising every
Flicker capability against seeded data — the pattern
`ash_authentication_phoenix` uses (a `dev/` directory compiled only in dev,
served with `mix dev`). It is the manual-QA surface for every other spec's
acceptance criteria, the screenshot source for docs, and — agent-natively —
the thing an agent drives with a browser tool to *see* a change working
rather than inferring it from tests.

## Scope

- **`dev/` Phoenix app** compiled only in `:dev` (`elixirc_paths`), started
  with `mix dev` (alias for running the dev endpoint). Bandit, LiveView,
  no asset pipeline beyond what the shipped hook needs — Tailwind via CDN
  or a minimal esbuild setup, whichever is less machinery.
- **Seeded Ash domain** on `Ash.DataLayer.Ets` — no database, no migrations,
  `mix dev` just works after clone. A small music-catalogue domain
  (`Dev.Music.{Artist, Album, Genre}`) with enough rows (~50 artists),
  variety (enum status, dates, numeric aggregates, relationships), and a
  policy-bearing resource so actor-scoping is *visible* (an actor toggle in
  the playground UI switches who's searching).
- **One page per capability**, added as each spec ships:
  - single select — form mode and controlled mode side by side (Spec 001)
  - multi-select with chips (Spec 002)
  - faceted search (Spec 003)
  - a pure-Elixir provider page using the in-memory/HTTP-style provider
    (Spec 004) — proving the no-Ash path in a place humans can poke at
  - theme showcase — the same select rendered in every preset (vanilla /
    Tailwind / daisyUI), mirroring Cinder's theme-showcase guide
- **Edge-state triggers**: a slow provider (configurable latency) to see
  loading/debounce/stale-cancellation behaviour, an erroring provider for
  error states, and an empty-results search.

## Non-goals

- Shipping any of this in the Hex package (`dev/` is excluded from
  `package.files`).
- A deployed public demo site — nice later, not this spec.
- Automated tests living in the playground (tests live in `test/`; the
  playground is for eyes and screenshots).

## Design

Follow `ash_authentication_phoenix`'s layout: `dev/` holds the endpoint,
router, layouts, and demo domain; `elixirc_paths(:dev)` includes it;
`application/1` starts the endpoint only in dev. Keep playground LiveViews
thin — they should read like the README examples, because they *become* the
documented examples (guides can quote them verbatim, and drift is visible).

Seed data is deterministic (no random generation) so screenshots are
reproducible and agents can assert against known records ("searching `cas`
yields Casey…").

## Acceptance criteria

- Fresh clone → `mix deps.get && mix dev` → working playground, no database
  or config required.
- Every shipped spec has a playground page exercising its acceptance
  criteria; adding a page is part of each spec's definition of done from
  Spec 001 onward.
- The actor toggle visibly changes search results on the policy-bearing
  resource.
- The slow/erroring providers make loading, stale-drop, and error states
  reproducible on demand.
- `mix hex.build` output contains nothing from `dev/`.

## Open questions

- Screenshot automation (for docs/README) — manual for now, or wire
  something like `wallaby`/playwright screenshots later?
