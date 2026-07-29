---
status: draft # draft | ready | in-progress | shipped
date: 2026-07-28
depends_on: [spec-003, spec-010, spec-018, spec-019, spec-020, adr-004, adr-006, adr-014]
---

# Spec 021: Facet value counts

The number beside a facet value — `Active 12`, `Archived 3`, `Unassigned 0` — is
what turns a filter from a guess into an exploration: you can see where the data
is before committing to narrowing it. This spec adds an optional provider
callback that computes those counts, and renders them in the three places facet
values are shown (value typeahead, the Spec 019 set editor, and committed pills).

[ADR-014](../adrs/adr-014-facet-counts-are-provider-computed-and-actor-scoped.md)
decides the hard parts: counts are provider-computed, run through the same
actor-scoped read as the search, exclude the counted facet's own constraint
(drill-down semantics), and are opt-in per facet.

## Scope

### Provider callback

```elixir
@callback facet_counts(
            query :: Flicker.Query.t(),
            facets :: [Flicker.Facet.t()],
            opts :: keyword()
          ) :: {:ok, %{atom() => %{term() => non_neg_integer()}}} | {:error, term()}
```

- Optional (`@optional_callbacks`). A provider without it has no counts, and
  every component renders as it does today.
- Returns counts keyed by facet key, then by value — the same cast values
  `Query.parse/2` produces, so lookup needs no normalisation.
- `opts` carries `actor` and `tenant`, exactly as `search/2` receives them.
- All requested facets arrive in **one** call, so a provider can batch. The
  built-in Ash implementation issues a single query.
- A value absent from the map means "not counted", rendered as no count, and is
  distinct from a value present with `0`.

`Flicker.Provider.run_facet_counts/4` is the dispatcher, mirroring
`run_search/3`, and returns `{:ok, %{}}` when the callback is absent so callers
need no `function_exported?/3` branching.

### Facet opt-in

`Facet` gains `:count` (boolean, default `false`), settable through the
derivation overrides:

```elixir
facets: [
  status: [count: true],
  worker: [count: true],
  created_at: [type: :date_range]   # ranges aren't counted — see Non-goals
]
```

### Ash implementation

`Flicker.Providers.AshResource.facet_counts/3` builds, for each requested facet,
the filter for the whole query **minus that facet's own clauses**, and aggregates
grouped by the facet's `Flicker.Facet.target/1`:

- Attribute targets group directly. Relationship and aggregate targets group
  through the path, the same resolution `to_filter/2` already performs.
- One `Ash.Query` per counted facet, executed together; the actor and tenant are
  set on every one (ADR-004).
- `:enum` facets return a count for **every** value in `:values`, including
  zeroes — a missing row and a genuine zero are different facts, and only the
  full set lets the editor show `Archived 0` rather than silently dropping it.
- Relationship facets count only the values present in the current result set,
  capped by `:count_limit` (default 50) — enumerating every related record to
  find the zeroes is unbounded work.
- Compiles only when `ash` is present (ADR-006).

### Rendering

Counts appear in three places, all sourced from one fetch:

- **Value typeahead** in the plain input — the count trails the value's label,
  dimmed.
- **The Spec 019 `Set` editor** — count right-aligned per row, which is where it
  matters most, next to a checkbox the user is about to tick.
- **Committed pills** (Spec 012) — off by default; opt-in, since a pill's count
  is the count of what's already applied and is more often noise than signal.

Rules:

- A **zero-count value stays visible and is dimmed**, not hidden. Hiding it
  answers "why did that option disappear?" with silence; dimming answers it with
  `0`. It remains selectable — a user widening a `multiple?` selection needs to
  reach it.
- Counts are **never rendered against stale results**. They ride Spec 020's
  request-supersession: a count response older than the rendered result set is
  dropped.
- Counts **never gate anything**. A missing, pending, or errored count renders no
  number and changes nothing else; `{:error, _}` from the callback is logged at
  debug and swallowed. A failed count must never break a working search.
- Formatted through `Facet.Format` so digits and grouping localise (ADR-013).
- Announced as part of the option's accessible name — "Active, 12 results" — not
  as a separate node a screen reader reads adrift from its label (Spec 007).

## Non-goals

- **No counts for range, numeric, date, or string facets.** A count per distinct
  date is meaningless, and per range-bucket is a histogram — a different feature
  with its own bucketing design. `count: true` on such a facet is ignored, with a
  compile-time warning from the derivation.
- **No count-driven ordering.** Sorting values by count is tempting and makes the
  list jump around as the user types. Values keep their declared/collated order
  (Spec 018).
- **No total result count.** Useful, unrelated, and cheaper; separate concern.
- **No histograms or sparklines** for numeric facets, however much the dial wants
  one.
- **No count caching.** Spec 020's non-goal for results applies identically, and
  for the same actor-scoping reason.

## Design

Counts are fetched **alongside** the search, not after it: one dispatch, two
async results, tagged with the same sequence number. The results render as soon
as they land; counts fill in when they do. That ordering matters — counts are
strictly supplementary, and blocking a result list on an aggregate would trade
the fast thing for the decorative one.

State is one assign, `:facet_counts` (`%{facet_key => %{value => count}}`, `%{}`
when absent), plus the seq it belongs to. Rendering is a lookup with a `nil`
fallback; no component branches on "are counts enabled".

Counting is skipped entirely when no facet has `count: true`, when no editor or
suggestion list is open, and when the provider lacks the callback — three cheap
guards before any query is built, because the common case is no counts at all.

## Acceptance criteria

- [ ] A provider without `facet_counts/3` renders exactly as today; no call is
      attempted and no error is logged.
- [ ] `run_facet_counts/4` returns `{:ok, %{}}` for such a provider without
      `function_exported?/3` checks at the call site.
- [ ] With `status: [count: true]` and no other active facet, each enum value's
      count equals the number of readable records with that value.
- [ ] **Drill-down**: with `tier:gold` active, `status` counts are computed with
      `tier:gold` applied and `status` omitted — selecting `status:active` does
      not zero its siblings (ADR-014's central criterion).
- [ ] Counts respect the actor: two actors with different policy visibility over
      the same data get different counts, and neither sees a count including
      records they cannot read.
- [ ] Counts respect free text: typing narrows the counts.
- [ ] An enum facet returns a count for every declared value, zeroes included; a
      zero-count value renders dimmed, remains selectable, and is not hidden.
- [ ] A relationship facet caps at `:count_limit` and renders no count for values
      beyond it, rather than a wrong one.
- [ ] `count: true` on a date/range/string facet is ignored and warns at compile
      time.
- [ ] A stale count response (older seq) is dropped and never rendered against
      newer results.
- [ ] `{:error, _}` from the callback leaves search fully functional with no
      counts rendered.
- [ ] Results render before counts arrive; a slow count never delays the list.
- [ ] Counts are skipped entirely when no facet opts in — asserted by a provider
      double that raises if called.
- [ ] Counts format per locale and fall back to plain digits without `localize`.
- [ ] Each option's accessible name includes its count as one string; axe-core
      clean.
- [ ] The Ash implementation issues one batched query for N counted facets, not N
      — asserted via query telemetry, not by reading the code.

## Open questions

None blocking.

- **Approximate counts at scale.** An exact count over a very large table is
  expensive; `~2k` is honest and much cheaper. Needs a provider-level opt-in and a
  rendering convention for approximation, plus a decision about whether an
  approximate count can ever be shown as exact (it cannot).
- **Numeric histograms.** The natural companion to the dial — showing where the
  values cluster — and a clearly separate feature with its own bucketing design.
- **Counting relationship zeroes.** Capping at `:count_limit` means a related
  value with zero matches is invisible rather than dimmed, which is inconsistent
  with the enum case. Resolving it needs a bounded way to enumerate candidate
  related records; deferred.
