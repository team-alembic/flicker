---
status: shipped
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
> non-private-ETS host never hits it.

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

> **Shipped.** `Flicker.Integrations.Cinder` (guarded by
> `Code.ensure_loaded?(Ash) and Code.ensure_loaded?(Cinder)` — `cinder`
> was already an optional dep from Level 1, so no `mix.exs` change was
> needed) ships `query/2` (Level 1's `base_query/1` recipe as one call),
> `restore/2`/`push_patch/4`/`encode_params/1`/`put_params/2`/
> `decode_input/1` (URL state), `facets/1` (the same registry resolution
> `Flicker.search/1` uses internally, so restore parses against
> identical facets), and `overlapping_fields/2` (the double-filter
> convention's drift guard). URL serialisation round-trips
> `Flicker.Query`'s new `:input` field — the verbatim typed string,
> re-`parse/2`d on restore — never `:text` or a reconstruction of
> `:facets`, both of which are lossy (`active?:TRUE` → `true`,
> `after:7d` → a resolved date, quoting gone). `Flicker.search/1` gained
> an optional `text` attr (adopted once, on the component's first mount
> — not a controlled value) so a restored URL pre-fills the input.
> The playground `/cinder-interop` page now runs on the adapter with
> `use Cinder.UrlSync` + `url_state` active alongside it;
> `test/flicker/cinder_interop_test.exs` drives the URL flow end to end
> (typing patches `flicker_q`, clearing removes it, a shared URL
> restores the narrowed table and pre-fills the input, a Flicker patch
> preserves Cinder's `sort` param, quoted/unicode inputs round-trip) and
> `test/flicker/integrations/cinder_test.exs` covers the adapter's own
> contract, including a trip wire asserting `flicker_q` stays disjoint
> from `Cinder.UrlSync.build_url/3`'s reserved keys and that Cinder's
> own URL rewrites preserve `flicker_q` as a custom param. One test-side
> lesson worth keeping: the base query the host composes must carry an
> explicit sort — with `Dev.Music`'s ETS data layer returning rows in
> arbitrary order, which 25 rows land on Cinder's first page is
> otherwise arbitrary too, which surfaced as a maddeningly intermittent
> "row missing from page 1" flake, not an error.

**Level 3 — upstream integration.** Cinder's `search` attr suggests a slot
where Flicker could *be* Cinder's search control, configured rather than
composed. Requires Cinder-side changes — a conversation with the Cinder
maintainers once Levels 1–2 prove the demand and the seam. Out of Flicker's
unilateral control; tracked here, not promised.

> **Not built — and deliberately not holding this spec open.** With
> Levels 1–2 shipped, everything within Flicker's unilateral control is
> done: the spec's own framing makes Level 3 an upstream conversation
> ("tracked, not promised"), gated on Cinder maintainers, with no
> Flicker-side work specified or specifiable until that conversation
> shapes the seam. Keeping a spec `in-progress` indefinitely for work
> this repo can't schedule would make the status meaningless — so the
> spec ships, and if the upstream conversation ever lands a concrete
> Cinder-side API, that becomes a new spec (likely mostly in Cinder's
> repo, per the open question below) rather than a reopened this one.

## Non-goals

- Flicker rendering tables or owning pagination/sort (Cinder's job).
- Replacing Cinder's column filters — coexistence, not conquest.
- Any Cinder version below the `query`-attr API.

## Acceptance criteria

- Level 1: typing `status:active worker:"Casey"` above a Cinder collection
  narrows it live; clearing the search restores the unfiltered collection;
  works actor-scoped end to end. Covered by a playground page and a test.
  **Shipped** — see the note above.
- Level 2: with the adapter, a shared URL reproduces both the Flicker query
  and Cinder's own state (page, sort); neither library clobbers the other's
  params; core suite still passes without `cinder` installed.

  **Shipped, with notes.** A shared `?flicker_q=...&sort=...` URL
  reproduces the narrowed table *and* Cinder's sort, verified end to end
  in `test/flicker/cinder_interop_test.exs`; param coexistence is
  guaranteed in both directions (the adapter's `put_params/2` only ever
  touches `flicker_q`; Cinder's `build_url/3` preserves `flicker_q` as a
  custom param — both covered in `test/flicker/integrations/cinder_test.exs`,
  including a trip wire against Cinder's reserved key list). The no-cinder
  story needed no work beyond the `Code.ensure_loaded?` guard: `cinder`
  already lived in `ash_deps/0` (dev/test-only, absent with
  `FLICKER_NO_ASH`), so the adapter, the upgraded playground page, and
  both test files are all inert on the no-ash CI leg. Notes: the restored
  `text` is adopted by `Flicker.search/1` once, on first mount only — a
  URL restored *after* mount (back/forward within a live session)
  re-filters the table but doesn't overwrite what's in the input, a
  deliberate trade against fighting the user's in-flight typing; and
  Cinder's `page` param coexists untested end to end (the seeded
  playground table fits interactions on one page) — its mechanism is
  identical to `sort`'s, which is tested.
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

  **Level 2 postscript:** the verdict held, with one amendment the
  "no new field" prediction didn't foresee: URL serialisation needs the
  *verbatim typed string* (`:text` + `:facets` are lossy in both
  directions — facet tokens are stripped from `:text`, and cast facet
  values can't reproduce the original literal), so `Flicker.Query`
  gained an `:input` field carrying exactly what `parse/2` was given.
  Still zero Cinder leakage: `:input` is a property of parsing itself
  (any consumer that persists/restores a query wants it), not a
  Cinder-shaped wrapper.

## Open questions

- Should the emitted value be `%Flicker.Query{}` (adapter converts) or a
  ready `Ash.Query`/filter (host converts less, couples more)? Leaning:
  emit both — the struct plus a `to_filter/1` — decided in Spec 003.
- Param namespacing convention for Level 2 (`?q=` vs `?flicker[q]=`).

  **Resolved: a flat, prefixed `?flicker_q=`.** Reading `cinder`'s
  actual `Cinder.UrlSync.build_url/3` (`~> 0.15`): Cinder claims the
  flat keys `page`, `sort`, `page_size`, `search`, `after`, `before`,
  plus one flat param *per filterable column field name* — so any bare
  key a column might be named (`q` included) is potentially Cinder's,
  and `?q=` can collide. A nested `?flicker[q]=` can't collide either,
  but Phoenix's bracket params decode to a nested map, which
  `build_url/3`'s flat merge (`URI.decode_query` → `Map.merge` →
  `URI.encode_query`) doesn't round-trip cleanly. `flicker_q` is flat
  (survives Cinder's rewrite as an ordinary custom param, verified by
  test), collision-proof in practice (no real column is named
  `flicker_q`), and self-describing in a shared URL.
  `Flicker.Integrations.Cinder.url_param/0` exposes it.
- Does Level 3 belong in Cinder's repo as "bring your own search
  component" rather than anything Flicker-specific? (Probably yes — the
  most ecosystem-healthy shape.)
