---
status: shipped # draft | ready | in-progress | shipped
date: 2026-07-28
depends_on: [spec-003, spec-018, spec-019, adr-003, adr-004, adr-006, adr-009]
---

# Spec 022: Recently-used facet values

Most filtering is repetition. The same three workers, the same two statuses, the
same region — over and over, retyped every time. Surfacing what a user actually
used last, at the top of the list, is the cheapest large improvement available to
a picker: no new interaction to learn, no new surface, and it collapses a search
into a single keystroke for the values that make up the bulk of real use.

This spec adds a `Recent` group at the top of facet value suggestions and the
Spec 019 set editor, ordered by **frecency** (recency weighted by frequency).
Flicker does not own the storage.

## Scope

### Host-provided storage

Flicker holds no persistence of its own — no ETS table, no cookie, no schema. A
host supplies two functions:

```elixir
# On a component, or globally in config.
recent_values: %{
  # Values used before, most-recent-first is not required — Flicker orders.
  load: (facet_key :: atom(), opts :: keyword() -> [{value :: term(), used_at :: DateTime.t(), count :: pos_integer()}]),
  record: (facet_key :: atom(), value :: term(), opts :: keyword() -> :ok)
}
```

`opts` carries `actor` and `tenant`, so a host can scope storage per user without
Flicker prescribing how. Omitting `recent_values` disables the feature entirely —
no group, no recording, no calls.

Rationale for pushing this out: recency data is user data. Where it lives (a
column, a `user_preferences` table, Redis, a session), how long it is kept, and
whether it is subject to a data-retention policy are all decisions a library
should not make on a host's behalf. Flicker owning a store would mean Flicker
owning a migration, a retention policy, and a GDPR question.

`Flicker.RecentValues.Ets` ships as a **dev/test/demo** implementation, used by
the playground (Spec 005) and clearly documented as non-durable.

### Ordering: frecency

```
score = count * decay(now - used_at)
decay(age) = 0.5 ** (age_in_days / half_life_days)   # half_life_days default 14
```

Half-life is configurable per facet. The properties that matter: a value used
once today outranks one used twice last month, and a value used constantly stays
near the top without any single use dominating. Ties break on `used_at`.

Sorting is Flicker's, from the raw triples — a host `load` returns facts, not an
opinion, so the ranking is testable in one pure function and consistent across
hosts.

### Recording

A value is recorded when it is **committed** — a suggestion chosen, a set-editor
selection confirmed, a token parsed cleanly from typed text on dispatch. Not on
hover, not on focus, not while typing, and never for a value that failed
validation (ADR-012). Recording is fire-and-forget: a failing `record` is logged
at debug and never surfaces to the user or blocks the query.

### Rendering

- A `Recent` group above the ordinary values, capped at `:recent_limit` (default
  5), in value typeahead and the Spec 019 set editor.
- The group is **suppressed while a search prefix is active** — once the user is
  typing, they have told you what they want, and a recency group is then just a
  duplicate row above the match. It reappears when the prefix clears.
- A value already selected is not repeated in `Recent`.
- Deduplicated against the main list by value, so the same value never appears
  twice on screen.
- With Spec 021 counts enabled, recent values carry their counts like any other.
- Labelled as a group for assistive tech, so "Recent, 3 items" precedes them and
  the ordering isn't mysterious (Spec 007).

### Authorisation and staleness

**Recency data is not an authorisation bypass, and this is the part most likely
to be got wrong.** A remembered value is only ever a *hint*; it must be resolved
through the normal actor-scoped path before display:

- Labels for recent values come from the provider's `fetch/2` (ADR-003), with the
  actor set (ADR-004). Any value that does not resolve — deleted, or no longer
  readable by this actor — is **silently dropped** from the group.
- Enum values are re-checked against the facet's current `:values`, so a value
  removed from the enum since it was used disappears rather than rendering as a
  broken suggestion.
- Nothing about a dropped value is announced or logged to the user: "you used
  this before but can't see it now" is itself a disclosure.

## Non-goals

- **No recent free-text searches.** Recording what a user typed is a much heavier
  privacy question (names, emails, and worse land in search boxes), and the value
  is lower. Separate spec, if ever.
- **No cross-user or "popular" values.** Aggregating across users leaks
  behaviour and needs a whole authorisation story of its own.
- **No Flicker-owned durable storage.** The ETS implementation is explicitly for
  dev and test.
- **No recent *records*** in the plain `Flicker.select` result list — plausible,
  but it changes result ordering rather than adding a group, and result relevance
  is the provider's job.
- **No sync across devices, no server-side pruning schedule.** Host's storage,
  host's lifecycle.

## Design

`Flicker.RecentValues` is a small pure module plus a thin dispatcher:

```elixir
@spec rank([{term(), DateTime.t(), pos_integer()}], keyword()) :: [term()]
@spec load(config :: map() | nil, facet_key :: atom(), keyword()) :: [term()]
@spec record(config :: map() | nil, facet_key :: atom(), term(), keyword()) :: :ok
```

`rank/2` takes `now` from opts rather than calling `DateTime.utc_now/0`, so the
decay curve is testable at fixed times. `load/3` and `record/4` are no-ops
returning `[]` / `:ok` when config is `nil`, which is what keeps every call site
branch-free.

Loading happens when a value list is about to be shown with an empty prefix —
once per open, not per keystroke, since the group is hidden while typing anyway.

## Acceptance criteria

- [ ] With no `recent_values` config, no `Recent` group renders and neither
      callback is ever called (asserted with a raising double).
- [ ] `rank/2` orders one-use-today above two-uses-a-month-ago at the default
      half-life, and is verified at fixed `now` values.
- [ ] `rank/2` is stable and deterministic for equal scores (ties break on
      `used_at`).
- [ ] A value is recorded on commit, and **not** on hover, focus, keystroke, or a
      validation failure.
- [ ] A `record` callback that raises or errors leaves the query unaffected.
- [ ] The `Recent` group renders with an empty prefix and disappears once a prefix
      is typed.
- [ ] A recent value that no longer resolves through actor-scoped `fetch/2` is
      dropped from the group, with nothing announced or shown in its place.
- [ ] A recent enum value no longer in the facet's `:values` is dropped.
- [ ] Two actors with different visibility see different `Recent` groups from the
      same underlying store.
- [ ] Already-selected and duplicate values never appear twice on screen.
- [ ] `:recent_limit` caps the group; the remainder still appear in the main list.
- [ ] The group has an accessible label announcing its name and size.
- [ ] The ETS implementation is documented as dev/test-only and is not referenced
      by any default config.

## Open questions

None blocking.

- **Half-life default.** 14 days is a guess informed by nothing but taste. Worth
  revisiting with real usage; the shape of the curve matters less than that it
  exists.
- **Recording typed-but-unselected values.** A user who types `worker:casey` in
  full and dispatches never touches a suggestion — recording that is right, but
  the commit point for free-typed tokens is fuzzier than for a chosen suggestion.
  Currently: on dispatch, once the token parses cleanly.
- **Interaction with Spec 021 zero counts.** A recent value with a current count
  of `0` is arguably the most useful thing to show (it tells you where the data
  went) and arguably the least. Currently shown, dimmed, like any zero.
