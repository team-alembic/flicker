---
status: proposed # proposed | accepted | superseded by adr-NNN
date: 2026-07-28
---

# ADR-014: Facet counts are provider-computed, actor-scoped, drill-down-correct, and opt-in

## Context

[Spec 021](../specs/spec-021-facet-value-counts.md) adds the number beside a
facet value — `Active 12`, `Archived 3` — which is what makes a filter
*explorable* rather than a guess: you can see where the data is before you
commit to narrowing.

A count looks like presentation and is actually three hard problems.

**It is data, and it leaks.** A count computed over an unscoped read tells the
user how many records exist that they cannot see. "Archived 47" when the actor
can read three of them discloses cardinality, and for a small enough set,
existence. [ADR-004](./adr-004-authorization-via-actor-and-policies.md) put
every read through `actor:` + policies precisely so Flicker never becomes the
component that leaks; a count taken outside that path would reopen it in the
one place that looks too trivial to audit.

**The naive count is wrong, not just imprecise.** If counts are computed against
the full active query, then the moment the user selects `status:active` every
sibling value reads `0` — because no record is simultaneously `active` and
`archived`. The user's own selection erases the information they needed. The
correct count for a value of facet `F` applies every *other* active facet and
the free text, but **not** `F`'s own constraint.

**It costs.** One aggregate per facet per open picker, on every keystroke, is a
straightforward way to melt a database — and the component that renders the
count is the component least able to judge whether that's affordable.

## Decision

**Counts are computed by the provider, through the same actor-scoped read as the
search, with the counted facet's own constraint excluded, and only when asked
for.**

Four parts:

**Provider-computed.** An optional callback, `c:Flicker.Provider.facet_counts/3`,
receives the query, the facets to count, and the same opts (`actor`, `tenant`)
`search/2` gets. No provider is required to implement it; a provider that
doesn't simply has no counts, and every component renders exactly as it does
today. Flicker never derives a count by counting returned results — that number
is the size of a *window* (Spec 010), not of a result set, and presenting it as a
count would be a lie that looks like a feature.

**Actor-scoped, no exceptions.** The count query is the search query: same
actor, same tenant, same policies (ADR-004). A count the actor could not have
reached by reading is not rendered, is not cached, and is not approximated. If a
provider cannot count under authorisation, it returns no count rather than an
unscoped one.

**Drill-down-correct.** For each facet `F` being counted, the provider applies
every other active facet and the free text, and omits `F`'s own clause. This is
the standard faceted-search semantic ("drill-down" counts) and it is what makes
the numbers useful after the first selection rather than before it only. For a
`multiple?: true` facet this is also what lets a user widen a selection — the
sibling values still carry the counts they'd add.

**Opt-in and bounded.** Counting is requested per facet (`count: true`), never
by default. The callback receives *all* requested facets in one call so a
provider can batch them into a single query rather than N; the built-in Ash
provider does exactly that. Counts ride the same request-supersession machinery
as the search ([Spec 020](../specs/spec-020-query-dispatch-policy.md)), so a
stale count is dropped rather than rendered against fresh results.

Rejected alternatives:

- **Count in core from the returned results** — free, and wrong: it counts the
  window, not the set, and silently reports different numbers as the user
  scrolls.
- **A separate unauthorised aggregate for speed** — the leak described above. Not
  a performance trade-off; a correctness and security failure.
- **Counts on by default** — the pleasant default and the expensive one. A host
  discovering Flicker's facets should not discover them via a load spike.
- **Counts computed against the full query including `F`'s own clause** —
  cheaper (one query serves every facet) and makes every sibling read zero the
  instant anything is selected, which is worse than showing nothing.
- **A dedicated `Flicker.Counts` behaviour, separate from `Provider`** — a second
  contract to implement, configure, and authorise, describing the same data
  source. Counting is something a provider does, not something a different object
  is.

## Consequences

Easier:

- Counts are as safe as search by construction, because they *are* search — one
  authorisation path to reason about and audit, not two.
- A provider that can count cheaply (a search engine with built-in facets, a
  materialised aggregate) can implement the callback natively and beat anything
  Flicker could compute generically.
- Drill-down semantics mean the numbers stay meaningful mid-exploration, which is
  the only state in which anyone actually reads them.
- Absent the callback, everything degrades to today's behaviour with no
  conditional rendering scattered through components.

Harder:

- **Drill-down counting is genuinely more expensive than one aggregate.** Each
  counted facet needs a different filter set. Batching helps, `count: true` being
  opt-in helps more, but a picker counting five facets on a large table is a real
  query and hosts must be able to see that cost coming — it needs saying plainly
  in the guide, not buried.
- The Ash provider's implementation is the non-trivial part of Spec 021: building
  N filter variants from one parsed query and aggregating them together, with
  relationship-path facets and aggregates as targets.
- Counts and results can disagree under concurrent writes. Accepted: they are two
  queries, and a count is an orientation aid, not a contract. Worth stating in the
  docs so nobody builds on count exactness.
- A fifth optional capability boundary (`ash`, `gettext`, LiveView floors,
  `localize`, now `facet_counts/3`) — though this one is a callback on an existing
  behaviour rather than a dependency, which is the cheaper kind.
