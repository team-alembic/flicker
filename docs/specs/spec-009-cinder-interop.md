---
status: in-progress
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

> **Shipped.** `Dev.Live.CinderInterop` (`/cinder-interop`) pairs
> `Flicker.search` with `Cinder.collection` over `Dev.Music.Artist`,
> actor-scoped via the same actor-toggle pattern as the other playground
> pages; `test/flicker/cinder_interop_test.exs` drives that exact
> LiveView end to end (narrows live, clears back to unfiltered, stays
> actor-scoped); [`guides/cinder-integration.md`](../../guides/cinder-integration.md)
> documents the recipe, quoting the playground LiveView verbatim. `cinder`
> landed as an optional dev/test dependency (`~> 0.15`, current Hex
> release as of this spec) — placed in `ash_deps/0`, not the general
> tooling deps, because `cinder` itself hard-depends on `ash`; putting it
> anywhere else would drag `ash` back into the no-`ash` CI leg's
> dependency tree, breaking the boundary ADR-006 exists to protect. One
> real-world wrinkle surfaced along the way: Cinder's own data load runs
> in a `start_async` task (a different process from whichever one seeded
> the data), which an `Ash.DataLayer.Ets` `private?: true` table (like
> `Dev.Music`'s) can't see into — worked around with
> `config :ash, disable_async?: true` in `:dev`/`:test` (Cinder-only,
> nothing under `lib/` checks that key); a Postgres-backed or
> non-private-ETS host never hits it. Levels 2 and 3 are unbuilt.

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
  **Shipped** — see the note above.
- Level 2: with the adapter, a shared URL reproduces both the Flicker query
  and Cinder's own state (page, sort); neither library clobbers the other's
  params; core suite still passes without `cinder` installed. **Not
  built.**
- The `on_change` payload designed in Spec 003 is sufficient for the
  adapter without Cinder-specific leakage into `Flicker.Query`.

  **Verdict: yes, as designed.** `{on_change, %Flicker.Query{}, filter}` —
  where `filter` is already the plain map `Ash.Query.filter_input/2`
  expects (`Flicker.Query.to_filter/2`'s output) — is exactly what Level
  1's recipe needed and nothing more: the host composes it onto a base
  `Ash.Query` with one `filter_input/2` call and hands the result to
  `Cinder.collection`'s `query` attr. Nothing about that payload
  mentions Cinder, references its types, or shapes itself around its API
  (`Cinder.collection`'s `query` attr just happens to accept the same
  `Ash.Query` any other consumer — a stream, a plain `Ash.read!/2` call —
  would). A Level 2 adapter would consume the same two values unchanged
  (`%Flicker.Query{}` for URL serialisation, `filter` — or
  `to_filter/2` re-run — for the composed query); no new field, no
  Cinder-shaped wrapper, is needed on `Flicker.Query` itself to support
  it. The one thing Level 1 leaves outside `on_change` entirely is
  Cinder's own state (page, sort, its column filters) — by design,
  that's Cinder's state, not Flicker's, and Level 2's job is coordinating
  the two in the URL, not merging them into one payload.

## Open questions

- Should the emitted value be `%Flicker.Query{}` (adapter converts) or a
  ready `Ash.Query`/filter (host converts less, couples more)? Leaning:
  emit both — the struct plus a `to_filter/1` — decided in Spec 003.
- Param namespacing convention for Level 2 (`?q=` vs `?flicker[q]=`).
- Does Level 3 belong in Cinder's repo as "bring your own search
  component" rather than anything Flicker-specific? (Probably yes — the
  most ecosystem-healthy shape.)
