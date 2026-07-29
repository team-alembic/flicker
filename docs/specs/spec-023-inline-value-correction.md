---
status: shipped # draft | ready | in-progress | shipped
date: 2026-07-28
depends_on: [spec-003, spec-007, spec-012, spec-018, spec-019, spec-020, adr-009, adr-012]
---

# Spec 023: Inline value correction, and the invalid-value policy

`status:activ` on a closed-set facet is a typo one character from working.
[ADR-012](../adrs/adr-012-parse-reports-invalid-facet-tokens.md) already ensures
it is caught, reported, and **never part of the query** — it contributes no
filter clause and does not leak into free text. This spec adds the obvious next
move: offer the fix, right there, as it is typed.

The framing matters and is easy to get wrong. This is **not** zero-results
recovery. For a closed-set facet the query never ran with `activ` in it, so there
are no zero results to recover from — the correction belongs at *validation
time*, on the error pill, before any dispatch. Flicker already holds everything
needed: ADR-012's `:not_in_values` reason carries the facet's complete value set,
and the reason itself says exactly what went wrong.

This spec also nails down the policy question ADR-012 left implicit: what a
component *does* with an invalid facet value.

## Scope

### The invalid-value policy

A new attr on `Flicker.search`, `Flicker.select`, and `Flicker.palette`:

```elixir
attr :on_invalid, :atom, default: :drop   # :drop | :require
```

- **`:drop`** (default) — the invalid token contributes no clause; every other
  facet and the free text dispatch normally. Per-facet independence, as decided in
  ADR-012: one typo never freezes results the user already has. The error is
  rendered conspicuously, because a silently-broader result set is the failure
  mode being designed against.
- **`:require`** — dispatch is withheld entirely while any token is invalid, and
  the component says so (`Flicker.Query.valid?/1` is the gate). For hosts where a
  partially-applied filter is worse than no update — an audit view, a
  destructive bulk action driven by a filter — this is the safe choice.

Under both policies the invariant from ADR-012 holds absolutely: **an
unvalidated value is never part of a query.** `:drop` and `:require` differ only
in whether the *rest* of the query proceeds.

An in-progress token — one the cursor is currently inside — is exempt from
`:require`'s gate. Half-typed input is expected to be invalid, and blocking
dispatch on every keystroke of `status:a`, `status:ac`, `status:act` would make
`:require` unusable.

### Corrections for closed-set facets

When a token is reported invalid with a reason that carries candidates —
`:not_in_values` (enum), and relationship values reachable via
`Facet.value_source/1` (Spec 018) — the component offers up to
`:correction_limit` (default 3) candidates:

- Ranked by a hybrid of prefix match, substring match, and Jaro–Winkler
  similarity, computed against both the value's **key** and its **label**, so
  `estab` finds `:established` and `Estab` finds `Established`.
- A candidate is offered only above a similarity floor. `status:banana` gets no
  suggestion at all, because three irrelevant guesses read as a broken component,
  whereas nothing reads as "that isn't a status".
- Rendered on the error pill (Spec 012) and in the editor's error region (Spec
  019): *Did you mean `Active`?* — the top candidate as a one-click/`Tab`-accept
  affordance, the rest listed below it.
- Accepting one splices the corrected canonical token via
  `FacetSuggest.replace_current_token/3` — the same mechanism as any suggestion —
  and dispatches immediately, like any facet commit (Spec 020).
- Keyboard: `Tab` accepts the top candidate when the caret is in the invalid
  token, `↓` moves into the candidate list. `Tab`-to-accept is the interaction
  worth getting right; it makes a typo cost one key.

For reasons with **no** candidate set, the correction is a *statement of shape*
rather than a guess, drawn from the reason itself: `:bad_date` renders
"expected a date like `2026-07-01`, `today`, or `7d`"; `:reversed_range` renders
"start date is after the end date" with a **swap** affordance, which is a
one-click fix rather than a suggestion; `:out_of_bounds` renders the permitted
range and offers the nearest valid value. Every string comes from
`Flicker.Messages` (ADR-009), localisable via `Localize.Message` (ADR-013).

### Error rendering

Enumerated here because ADR-012's whole cost/benefit rests on the error being
conspicuous:

- The pill carries an error theme part, a visible icon (never colour alone), and
  the message as text — not a tooltip, not a title attribute, not hover-only.
- `aria-invalid="true"` plus `aria-describedby` pointing at the message, so the
  reason reaches a screen reader at the field, not as a detached announcement.
- Announced once when the token settles as invalid — debounced, so mid-typing
  states don't produce a stream of announcements.
- Under `:require`, the withheld-dispatch state is itself announced and visible
  ("filter not applied — fix the highlighted facet"), because a search box that
  silently stopped searching is broken.
- New theme parts: `:facet_pill_invalid`, `:facet_error_message`,
  `:facet_error_icon`, `:facet_correction`, `:facet_correction_accept`,
  `:dispatch_blocked`.

## Non-goals

- **No data-driven "did you mean" for `:string` facets or free text.** This is the
  genuinely different mechanism: a string value always casts, so the query *does*
  run and *can* return nothing, and suggesting an alternative requires fuzzy
  matching against actual data (a trigram index, a search engine's own
  suggester) — a provider capability, not a closed set Flicker already holds.
  Deferred to its own spec, and deliberately not conflated with this one.
- **No auto-correction.** Flicker never silently rewrites what the user typed.
  Correction is always offered and always accepted explicitly, because a filter
  that quietly means something other than what is on screen is worse than one that
  is visibly wrong.
- **No spelling correction of free text.**
- **No cross-facet suggestions** ("you typed `status:melbourne` — did you mean
  `city:melbourne`?"). Appealing, and a bigger ranking problem across the whole
  registry; possible follow-up.

## Design

`Flicker.Correction` is one pure module:

```elixir
@spec candidates(Facet.t(), raw :: String.t(), reason :: atom(), params :: map(), keyword()) ::
        [%Flicker.Correction{value: term(), label: String.t(), score: float()}]

@spec explain(Facet.t(), reason :: atom(), params :: map(), keyword()) ::
        %{message: String.t(), fix: nil | {:swap, term()} | {:clamp, term()} | {:replace, term()}}
```

Pure, total, and testable without a browser or a provider: `candidates/5` reads
the closed set out of `params` (or the facet), and `explain/4` maps a reason to a
message and an optional mechanical fix. `{:swap, _}` and `{:clamp, _}` are why
this isn't only a suggestion engine — a reversed range and an out-of-bounds
number have *correct* answers, not guesses, and offering the answer beats
offering advice.

Relationship-facet candidates need the provider (the closed set isn't local), so
they are fetched through `Facet.value_source/1` under the actor (ADR-004) — a
correction must never suggest a record the actor cannot read. That fetch is
subject to Spec 020's supersession and is skipped entirely when the reason carries
its own candidates.

## Acceptance criteria

Policy:

- [ ] Under `:drop`, `status:activ price:10..50` dispatches with the price filter
      applied and the status token contributing nothing.
- [ ] Under `:require`, the same input dispatches nothing, and the blocked state is
      both visible and announced.
- [ ] Under both, no query ever contains a value that failed validation —
      asserted directly against the filter passed to the provider.
- [ ] Under `:require`, a token the caret is currently inside does not block
      dispatch; the same token blocks once the caret leaves it.
- [ ] Removing or correcting the invalid token restores normal dispatch under
      `:require`.

Corrections:

- [ ] `status:activ` offers `Active` as the top candidate; accepting it with `Tab`
      produces `status:active` and dispatches once.
- [ ] Matching works against both value keys and labels, case-insensitively.
- [ ] `status:banana` offers no candidates and shows the shape message instead.
- [ ] At most `:correction_limit` candidates render, best first.
- [ ] `created:2026-07-30..2026-07-01` offers a **swap** that produces a valid
      range in one action.
- [ ] `price:900` with `bounds: %{min: 0, max: 500}` offers `500` as a clamp.
- [ ] `created:nonsense` renders the expected-shape message with a real example.
- [ ] Relationship candidates are actor-scoped: a value only readable by another
      actor is never suggested.
- [ ] Every reason atom from Spec 018's table produces either candidates or a
      shape message — none renders an empty error.
- [ ] `Flicker.Correction` is covered entirely by unit tests, including a property
      test that `candidates/5` never returns a value outside the facet's closed
      set.

Rendering:

- [ ] The error is text plus an icon, never colour alone, and is not hover-only.
- [ ] `aria-invalid` and `aria-describedby` are set on the pill/field and point at
      the message.
- [ ] The invalid state is announced once when settled, not per keystroke.
- [ ] axe-core clean in the invalid state, with a correction offered, in light and
      dark.
- [ ] The whole correct-a-typo flow is completable with the keyboard alone.

## Open questions

None blocking.

- **Similarity floor.** Jaro–Winkler ≥ 0.75 is a starting guess; the failure mode
  to avoid is confidently wrong suggestions on short values, where a single
  character is a large proportion of the string. May need a length-sensitive
  threshold.
- **Multiple invalid tokens.** Currently each gets its own error and its own
  correction. Under `:require` that could mean several fixes before anything
  dispatches; a "fix all" affordance might be warranted if it shows up in practice.
- **`:require` as the better default.** It is the safer behaviour and the more
  surprising one. Defaulting to `:drop` keeps continuity with ADR-012's per-facet
  independence, but a host filtering a destructive action would rather have been
  defaulted into safety.
