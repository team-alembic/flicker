---
status: proposed # proposed | accepted | superseded by adr-NNN
date: 2026-07-28
---

# ADR-011: A rich facet editor is a modal sub-context that commits once, serialising back to token text

## Context

Spec 003 built faceted search on one invariant: a facet is a `key:value`
substring of the typed input, `Flicker.Query.parse/2` is the only thing that
turns text into filters, and `Flicker.Query.input` — the verbatim string —
is the canonical, re-parseable source of truth. Spec 009's URL state and
Spec 012's pills both lean on that: pills *render* a parsed query, they
don't own it.

[Spec 018](../specs/spec-018-rich-facet-types.md) adds facet types whose
values can't sensibly be typed character by character — a date range, a
bounded numeric range, a multi-value enum. Those want real controls: a
two-month calendar with a hover band, a dual-thumb slider, a checkbox list.

That raises two questions the existing architecture doesn't answer.

**Where does the value live?** If a calendar holds a `{Date, Date}` pair in
component state alongside the text buffer, there are suddenly two sources of
truth. `input` no longer round-trips, the URL can't restate the query, and
Spec 012's pills have to render from two places.

**When does the query run?** The current model is per-keystroke: every
change re-classifies the cursor and re-queries. For a plain string facet
that's right — you want results narrowing as you type. For a date range it's
actively wrong: picking a start date fires a query for a range that doesn't
exist yet, and half the interactions in a calendar (paging months, hovering)
aren't value changes at all. It also means the main picker's keyboard model
(↑/↓ through a listbox, Enter to choose) is competing with the editor's
(arrow keys move between days).

## Decision

A rich facet editor is a **modal sub-context** over the main picker, and its
only output is **token text**.

**One source of truth.** An editor produces a string. Choosing Jun 18 – Jul
12 in the calendar produces `created:2026-06-18..2026-07-12`; choosing the
"Last 30 days" preset produces `created:last-30-days`. That string is spliced
into the input via the existing `Flicker.FacetSuggest.replace_current_token/3`
and re-parsed by `Flicker.Query.parse/2` like anything the user typed by
hand. No editor holds committed state; no component state shadows `input`.
Semantic presets serialise as their **id**, not their resolved range, so a
saved or shared query stays relative.

**Modal focus.** Opening an editor moves focus out of the text input and into
the editor's pop-out, which is a `role="dialog"` labelled by the facet. While
it is open the main picker's keyboard model is suspended: arrow keys, Enter,
and Home/End belong to the editor. `Escape` closes it and discards, returning
focus and the caret to where they were. The pop-out is a separate surface from
the suggestion listbox, not a row inside it — the user is editing one facet,
not choosing among results.

**Atomic commit.** No query is dispatched while an editor is open. The
editor commits exactly once, when its value is *complete* — both endpoints of
a range, a preset chosen, a selection confirmed — and that single commit
splices the token, closes the pop-out, restores focus, and triggers one
`on_change`. A half-made selection is a draft: visible in the editor's own
footer, invisible to the query.

**An editor is a Flicker component, and the value-set editor is driven by one
value source.** *(Amended during implementation — see the note at the end of
this section.)* A facet whose values come from a set — an `:enum`
facet's closed picklist, a relationship facet's related records — is edited by
a nested `Flicker.select`, not by a bespoke list. The two differ only in the
provider behind them: `Flicker.Providers.Static` over the enum's values,
`Flicker.Providers.AshResource` over the related resource (which is already
what `Flicker.FacetSuggest.related_search/3` builds today). `multiple?: true`
maps onto Spec 002's multi-select and chips; Spec 017's value colours and Spec
013's `:selected` slot come along unchanged. One editor module, one keyboard
model, one theme surface, one set of a11y behaviour — and every improvement to
`Flicker.select` improves facet editing for free.

The nested select runs in controlled mode with **no `facets` of its own**.
Facet editing never recurses: an editor may contain a select, and a select may
open an editor, but an editor's select is a leaf.

**Amendment (implementation).** The *literal* nesting doesn't work.
`Flicker.select`'s controlled mode notifies via `send(self(), {on_select, …})`,
and `self()` inside a `Phoenix.LiveComponent` is the **host LiveView**, not the
enclosing component — so a nested select can never hand its selection back to
the editor containing it without every host adding a `handle_info` clause to
forward it. That is exactly the boilerplate a library must not impose.

What survives is the part that mattered: `Flicker.Facet.value_source/1` is the
single definition of a facet's candidate values, and the enum and relationship
editors are the same code with a different provider behind them. The set editor
renders that list itself, with its events targeted at the component that owns
it. What is genuinely lost is inheriting `Flicker.select`'s listbox behaviour
for free — windowing over a very large related set is the notable gap.

**An editor whose value is complete in one interaction needs no pop-out.**
Modality exists to stop a half-made value from dispatching a query and to give
a multi-step control its own keyboard model. A `:boolean` facet has neither
problem: it is a **switch**, one flick is a complete value, and it can live
directly in the facet's pill and commit on toggle. The rule is therefore
*atomic commit is mandatory, a pop-out is only what multi-step values need* —
the switch is the degenerate case where those coincide. "Filtered false" and
"not filtered at all" stay distinct: the switch expresses the first, the pill's
remove control the second.

**Plain text is the exception, and stays as it is.** A `:string` facet has no
editor. Its value is typed into the main input, re-classified and re-queried
per keystroke exactly as today, because incremental narrowing *is* the useful
behaviour there. The same holds for the free-text portion of the query.
"Modal editor" is a property of a facet's type, not of facets in general.

Rejected alternatives:

- **Editor state as first-class query state** (a `%Query{}` field holding
  typed values instead of text) — kills the `input` round-trip that Spec 009
  and every persisted or shared query depends on, and forces every consumer
  to understand a second representation.
- **Editors inline in the suggestion listbox** — one keyboard model has to
  win, and neither can lose gracefully; a calendar's arrow keys and a
  listbox's arrow keys mean different things.
- **Commit per interaction (per-keystroke semantics extended to editors)** —
  dispatches queries for incomplete ranges, and makes every month-page a
  server round-trip for the host's data.
- **A dedicated editor for `:string` too** — adds a modal step to the one
  case where typing straight through is faster than any control.
- **A bespoke checkbox list for enum facets** — reimplements the listbox,
  keyboard model, chips, empty state, and a11y that `Flicker.select` already
  has, and would drift from the relationship case that is structurally
  identical.

## Consequences

Easier:

- Editors are pure presentation. Anything an editor can express, a user can
  type; anything a user can type, an editor can be opened on. Spec 012's pills
  become re-editable for free — click a pill, open the same editor on that
  token.
- Round-trip, URL state, Cinder interop, and `to_filter/2` need no changes
  whatsoever: they only ever see text and the parse of it.
- Editor logic is testable without a browser. The serialise/parse pair is a
  pure function per type; only focus behaviour needs the Spec 007 browser
  suite.
- Set-valued facets need almost no new code: an enum editor is
  `Flicker.select` over a `Static` provider built from the facet's own
  `:values`, so the editor module is shared with relationship facets and
  only the provider differs.
- A host can supply its own editor for a facet (a fiscal-quarter picker, a
  site map) without forking anything, as long as it emits a token the facet's
  type can parse.

Harder:

- Every editor's expressiveness is bounded by the grammar. A control that
  can't serialise to a `key:value` token can't exist — which is a real
  constraint on future types (geographic regions, arbitrary set algebra) and
  should be treated as a design gate, not a bug.
- Focus management becomes a first-class concern: up to three nested surfaces
  (palette overlay → editor pop-out → the editor's own select listbox) with a
  correct focus trap and restore in each, and screen-reader announcements for
  entering and leaving the editor (Spec 007). The "leaf select" rule is what
  keeps that depth bounded, and it needs to be enforced, not just documented.
- `Flicker.select` is now load-bearing for facet editing as well as record
  picking, so a change to its keyboard or focus behaviour has a second set of
  callers to regression-test.
- "Complete" has to be defined per type, and an editor has to render its own
  draft state so an incomplete value doesn't look inert. The date picker's
  `Jun 18, 2026 → pick an end date` footer is the pattern.
- Because a commit is a single splice, an editor cannot progressively refine a
  query the way typing does — for a facet where live feedback genuinely helps,
  the answer is a `:string` facet, not an editor with per-interaction commits.
