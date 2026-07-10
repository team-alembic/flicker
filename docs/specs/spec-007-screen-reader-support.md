---
status: draft
date: 2026-07-10
depends_on: [spec-001, adr-009]
---

# Spec 007: First-class screen-reader support

Most select libraries stop at "we set the ARIA attributes". First-class
means the component is *verified pleasant to use* with real assistive
technology — announced, navigable, and predictable — and that we can say so
in docs with evidence. This is a differentiator: accessibility review is
where custom comboboxes usually fail audits, and "passes with VoiceOver,
NVDA and JAWS" is a reason to pick Flicker over hand-rolling.

## What "first-class" means (scope)

1. **Correct semantics** (baseline, owned by
   [Spec 001](./spec-001-portable-single-select.md)): the WAI-ARIA APG
   editable-combobox pattern — `role="combobox"`, `aria-expanded`,
   `aria-controls`, `aria-activedescendant` (focus stays in the input;
   option highlight moves via active-descendant, not DOM focus),
   `aria-autocomplete="list"`, labelled listbox and options.
2. **Announcements**: a polite live region announcing state the visuals
   convey silently — result counts on each search ("5 results available"),
   loading ("Searching…"), empty ("No results for 'x'"), selection made,
   chip removed, at-`max_selections`. Every announcement string is a
   messages-module key
   ([ADR-009](../adrs/adr-009-messages-module-for-user-facing-text.md)), so
   the key list *is* the auditable announcement inventory.
3. **Multi-select semantics** ([Spec 002](./spec-002-multi-select-chips.md)):
   chips as a labelled list; each remove control named ("Remove Casey
   Nguyen"); selection changes announced; backspace-removal announced.
4. **Faceted-search semantics** ([Spec 003](./spec-003-faceted-search.md) —
   the novel, hardest part): cursor-context changes must be announced
   ("Suggesting values for status", "Searching workers") or the state
   machine is invisible to non-sighted users. This lands with Spec 003 but
   the live-region plumbing is built here.
5. **Verification, not vibes**:
   - automated: axe checks run against the playground pages in CI (the
     playground, [Spec 005](./spec-005-dev-playground.md), is the fixture).
   - manual: a written per-release test script (steps + expected
     announcements) executed against an AT matrix — VoiceOver+Safari,
     NVDA+Firefox, JAWS+Chrome as budget allows; results recorded in the
     repo.
6. **A published accessibility statement** in hexdocs: pattern followed,
   AT matrix tested, known gaps. Honest and versioned.

## Non-goals

- WCAG certification/VPAT paperwork.
- High-contrast/forced-colors visual theming (a theme-preset concern,
  [ADR-002](../adrs/adr-002-rendering-via-slots-and-theme-map.md)).
- Voice-control (Dragon) and switch-access testing in v1 — noted in the
  statement as untested.

## Design notes

One shared live-region element per component instance (not per message),
`aria-live="polite"`, debounced so rapid keystrokes don't queue a backlog
of stale counts. Announcements are derived from the same state that drives
rendering — never a parallel code path that can drift. aria-activedescendant
over roving focus because the input must keep receiving keystrokes.

## Acceptance criteria (draft)

- axe reports zero violations on every playground page, enforced in CI.
- The manual script passes on VoiceOver+Safari and NVDA+Firefox: every
  state transition in the Spec 001 keyboard map has a defined, observed
  announcement.
- Result-count announcements reflect the *latest* query only (stale-result
  cancellation extends to announcements).
- All announcement strings resolve through the messages module — a grep for
  user-facing literals in templates finds none.
- The accessibility statement ships in the hexdocs guides.

## Open questions

- JAWS licensing/access for the matrix — test lab, or community-verified?
- Can announcement expectations be asserted in ExUnit (live-region content
  as rendered HTML) to catch regressions between manual passes? (Likely
  yes — the live region is just DOM.)
