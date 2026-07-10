---
status: draft
date: 2026-07-10
depends_on: [spec-003, adr-006]
---

# Spec 009: Cinder interop — `Flicker.search` drives a Cinder collection

The pairing the two libraries were born for: a `Flicker.search` filter bar
above a Cinder table, Datadog syntax in, live-narrowing collection out.
Flicker answers "which subset?", Cinder renders it. Future goal — nothing
here blocks specs 001–008 — but specced now because the seam it needs
(what exactly `on_change` emits) is being designed in
[Spec 003](./spec-003-faceted-search.md) and should be shaped with this
consumer in mind.

## What Cinder gives us today (verified against `cinder` main, 2026-07-10)

- `Cinder.collection`/`table` accepts **`query`** — a pre-built
  `Ash.Query` — alongside `resource`, plus `actor`/`tenant`/`scope`.
  External filtering by query composition is possible *now*.
- `on_query_change` and a refresh mechanism exist for reacting to and
  re-running queries.
- Cinder has its own filter controls (`show_filters`, filter slots) and its
  own URL-state manager (`UrlSync`) — the overlap Flicker must not fight.

## Interop levels

**Level 1 — recipe (works with no code in either library).** Controlled
`Flicker.search`; the host's `handle_info`/`on_change` composes the emitted
filter onto a base query and passes it to Cinder's `query` attr:

```heex
<Flicker.search resource={Client} actor={@current_user}
  facets={[:status, :worker, :city]} on_change={...} />
<Cinder.collection query={@filtered_query} actor={@current_user} ...>
```

Deliverable: a playground page ([Spec 005](./spec-005-dev-playground.md))
and a hexdocs guide, tested, so the recipe can't rot.

**Level 2 — blessed adapter (`Flicker.Integrations.Cinder`).** Removes the
boilerplate and resolves the two real conflicts:

- **URL state**: both libraries want query params. The adapter serialises
  `%Flicker.Query{}` into a namespaced param (`?q=...`) coordinated with
  Cinder's `UrlSync` so back/forward/share works with both active.
- **Double-filter UX**: guidance + helpers for facets and Cinder column
  filters coexisting (rule of thumb: a field is filtered in one place, not
  both; `show_filters={false}` when Flicker owns filtering).

`cinder` becomes an optional dependency on the exact pattern
[ADR-006](../adrs/adr-006-core-depends-only-on-provider.md) established for
`ash`: `Code.ensure_loaded?` guard, no-cinder CI unaffected, adapter
compiles only when Cinder is present.

**Level 3 — upstream integration.** Cinder's `search` attr suggests a slot
where Flicker could *be* Cinder's search control, configured rather than
composed. Requires Cinder-side changes — a conversation with the Cinder
maintainers once Levels 1–2 prove the demand and the seam. Out of Flicker's
unilateral control; tracked here, not promised.

## Non-goals

- Flicker rendering tables or owning pagination/sort (Cinder's job).
- Replacing Cinder's column filters — coexistence, not conquest.
- Any Cinder version below the `query`-attr API.

## Acceptance criteria (draft)

- Level 1: typing `status:active worker:"Casey"` above a Cinder collection
  narrows it live; clearing the search restores the unfiltered collection;
  works actor-scoped end to end. Covered by a playground page and a test.
- Level 2: with the adapter, a shared URL reproduces both the Flicker query
  and Cinder's own state (page, sort); neither library clobbers the other's
  params; core suite still passes without `cinder` installed.
- The `on_change` payload designed in Spec 003 is sufficient for the
  adapter without Cinder-specific leakage into `Flicker.Query`.

## Open questions

- Should the emitted value be `%Flicker.Query{}` (adapter converts) or a
  ready `Ash.Query`/filter (host converts less, couples more)? Leaning:
  emit both — the struct plus a `to_filter/1` — decided in Spec 003.
- Param namespacing convention for Level 2 (`?q=` vs `?flicker[q]=`).
- Does Level 3 belong in Cinder's repo as "bring your own search
  component" rather than anything Flicker-specific? (Probably yes — the
  most ecosystem-healthy shape.)
