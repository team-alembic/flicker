# Accessibility

Flicker's combobox, multi-select, faceted search, and command palette are
built to the WAI-ARIA APG editable-combobox pattern, with screen-reader
announcements for every state change the visuals convey silently. This
guide is the accessibility statement — what's automated and verified, what
still needs a manual assistive-technology pass — plus the test script for
running that manual pass.

## Accessibility statement

**Pattern followed**: the [WAI-ARIA APG "Editable Combobox With List
Autocomplete"
pattern](https://www.w3.org/WAI/ARIA/apg/patterns/combobox/) — `role`
stays on the text input (`role="combobox"`), DOM focus never leaves it,
and the highlighted option is communicated via `aria-activedescendant`
rather than moving real focus into the listbox. This holds across
`Flicker.select/1` (single- and multi-select), `Flicker.search/1`
(standalone faceted search), and `Flicker.palette/1` (a
`Flicker.select/1` inside a labelled `role="dialog"` overlay).

**Semantics**, per component:

- The input carries `role="combobox"`, `aria-expanded` (kept in exact
  sync with whether the listbox is actually rendered — never a stale
  `true` over an empty popup), `aria-controls` pointing at the listbox,
  `aria-autocomplete="list"`, and `aria-haspopup="listbox"`.
- The listbox (`role="listbox"`) has an accessible name via
  `aria-labelledby`, pointing at the same visually-hidden `<label>` that
  labels the input — the listbox and the input it belongs to are
  announced as one thing, not an anonymous popup.
- Options (`role="option"`) get `aria-selected` toggled by the keyboard
  hook as the active-descendant index moves; each result renders as one
  `<li>` with a plain-text (or slotted) label.
- Multi-select's chip list is a labelled `role="list"`
  (`aria-label="Selected items"`) of `role="listitem"` chips; each chip's
  remove control carries an `aria-label` naming exactly what it removes
  ("Remove Casey Nguyen"), never a bare "Remove".
- `Flicker.palette/1`'s overlay is `role="dialog"` `aria-modal="true"`
  with an `aria-label`, a focus trap, and focus restored to whatever had
  it before the palette opened.

**Announcements**: one polite live region
(`aria-live="polite"`) per component instance — not one per message, and
not one per concern — so a screen reader never gets more than one
in-flight announcement from a single Flicker component competing with
itself. Its content is a pure function of the same assigns that drive the
visible render (`Flicker.Components.Select.announcement/1`,
`Flicker.Components.Search.announcement/1`) — there is no second,
independently-updated "what did we last announce" assign that visible
state and announced state could drift apart on. Covered:

- result counts, after every search settles ("5 results available", "No
  results available") — and only the *latest* query's count, ever: the
  same `start_async/3` same-name-cancellation LiveView provides for
  render state (a slower response for an earlier keystroke is discarded
  before it reaches any assign) means a stale count can't reach the
  announcement either, since the announcement reads off exactly the
  assigns the cancellation already protects.
- loading ("Loading...") while a search is in flight, ahead of the count.
- selection made ("Casey Nguyen selected") once a single-select choice
  closes the listbox.
- the multi-select running total ("2 items selected") on every chip
  add *or* remove — a chip removed is simply the count going down, so
  one message key covers both without a second, harder-to-verify
  "you just removed X" sentence naming a chip that's no longer part of
  render state by the time it would be spoken.
- reaching `max_selections` ("Maximum of 2 selections reached").
- faceted-search cursor-context changes (`Flicker.search/1`, and
  `Flicker.select/1` when given `facets`) — "Typing a facet name",
  "Typing a value for status", "Typing free text" — plus the matching
  suggestion count for whichever context is active, so the otherwise
  invisible key/value/free-text state machine is legible to someone who
  can't see the listbox change shape.

Rapid keystrokes don't queue a backlog of stale announcements because the
announcement can only change as often as the underlying render state
does, and that in turn is gated by the same `phx-debounce={@debounce}`
that already governs when a `query` event reaches the server at all — no
separate announcement-only debounce timer to keep in sync with the render
one.

Every one of these strings — visible text and announcement alike — comes
from `Flicker.Messages` (see `Flicker.Messages.English` for the complete,
documented key list), per
[ADR-009](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-009-messages-module-for-user-facing-text.md).
There are no inline user-facing literals in any template; a grep for bare
text nodes in `lib/flicker/components/*.ex` outside `message/2` calls
finds none, and CI can re-run that grep as a regression check.

**What's automated today**:

- ExUnit assertions on live-region content (the rendered
  `#<id>-announcer` element) for every server-reachable transition in the
  [Spec 001 keyboard map](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-001-portable-single-select.md#keyboard-interaction--the-full-map):
  opening, typing (narrowing/zero/loading), selecting, escape/close,
  clearing, chip add/remove (button and `Backspace`), `max_selections`,
  and facet cursor-context changes — see
  `test/flicker/select_announcements_test.exs` and
  `test/flicker/search_announcements_test.exs`.
- A dedicated regression test proving stale-result cancellation reaches
  the announcement text, not just the visible result list
  (`"the announced count reflects only the latest query, never a slower
  stale one"`).
- ARIA semantics (role/aria-expanded/aria-controls/aria-labelledby/
  aria-selected/labelled chip list) are exercised incidentally by the
  full component test suite's HTML assertions.

**What still needs a manual pass** (tracked in
[Spec 007](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-007-screen-reader-support.md),
left `in-progress` deliberately — this guide is not a claim that the
matrix below has been run):

- The manual AT test script below, executed against VoiceOver+Safari,
  NVDA+Firefox, and (budget/licensing permitting) JAWS+Chrome, with
  results recorded in the repo.
- An automated `axe-core` run against the `dev/` playground pages in CI
  (the playground is Spec 005's fixture) — no axe check has been wired
  up yet.
- Arrow-key/`Enter` highlight movement and the `aria-activedescendant`
  wiring are client-side JS (`Flicker.Components.Select`'s colocated
  `.Nav` hook) that ExUnit/PhoenixTest cannot drive — they're implemented
  and covered by the manual script, not by ExUnit.
- Voice-control (Dragon) and switch-access are explicitly out of scope
  for v1 (Spec 007's non-goals) and untested.
- High-contrast/forced-colors visual theming is a theme-preset concern,
  not this guide's.

Until that manual pass is recorded, treat "first-class screen-reader
support" as *implemented and unit-verified*, not yet *field-verified* —
the honest, versioned distinction this statement exists to make.

## Manual AT test script

Run this against each browser/AT pair in the matrix
(VoiceOver+Safari, NVDA+Firefox, JAWS+Chrome). Use the `dev/` playground
(`mix dev` or however your checkout runs it) — the single-select, multi-select,
and faceted-search pages. For each step, confirm the **expected
announcement** is what the AT actually speaks, not just that the visual
state is correct.

### Single-select (`Flicker.select/1`, single mode)

| # | Step | Expected announcement |
|---|---|---|
| 1 | Tab to the search input | Input's accessible name is spoken (its placeholder/label text); combobox role announced |
| 2 | Press `ArrowDown` | Listbox opens, first option becomes active; "N results available" |
| 3 | Type a query that narrows results (e.g. a name prefix) | "N results available" (or "1 result available" — singular) reflecting the narrowed count |
| 4 | Type a query matching nothing | "No results available" |
| 5 | Clear the query back to empty while focused | Full unfiltered "N results available" |
| 6 | `ArrowDown`/`ArrowUp` through options | Each option's label spoken as it becomes active (via `aria-activedescendant`) |
| 7 | Press `Enter` on a highlighted option | Listbox closes; "<Name> selected" |
| 8 | Press the clear-selection button | Selection cleared; announcement no longer mentions the cleared item |
| 9 | Re-open and press `Escape` | Listbox closes, typed text preserved; no stale result-count announcement lingers |
| 10 | Press `Escape` again (closed, text present) | Input clears |
| 11 | Click outside the component while open | Listbox closes without selecting |

### Multi-select (`Flicker.select/1` with `multiple`)

| # | Step | Expected announcement |
|---|---|---|
| 1 | Select a first result | "1 item selected" |
| 2 | Select a second result | "2 items selected" |
| 3 | Activate a chip's remove button | "1 item selected"; the remove button's own accessible name named the chip before activation ("Remove <Name>") |
| 4 | With the input empty, press `Backspace` | Last chip removed; selected-count announcement decreases |
| 5 | Select up to `max_selections` | "Maximum of N selections reached" once the cap is hit; no further options rendered |
| 6 | Remove a chip while at the cap | Cap message stops; selection becomes possible again |
| 7 | Press "Clear all" | Selected count returns to "No items selected"; all chips gone from the labelled list |

### Faceted search (`Flicker.search/1`, and `Flicker.select/1` with `facets`)

| # | Step | Expected announcement |
|---|---|---|
| 1 | Type the start of a facet key (e.g. `stat`) | "Typing a facet name"; "N matching facets" |
| 2 | Pick a facet-key suggestion | Text completes to `status:`; "Typing a value for status"; the value picklist's count |
| 3 | Pick a facet value | Token completes (e.g. `status:active `); cursor context returns to free text |
| 4 | Continue typing free text after a completed facet | "Typing free text"; ordinary result/suggestion count, no stale facet-context announcement |
| 5 | Type an unrecognised `key:value` pair | Degrades to free-text context; no crash, no stuck facet-context announcement |
| 6 | Type a relationship facet's value prefix (e.g. `genre:In`) | "Typing a value for genre"; nested search runs; "Loading..." while in flight, then a count |

### Command palette (`Flicker.palette/1`)

| # | Step | Expected announcement |
|---|---|---|
| 1 | Trigger the `activate_with_keyboard` chord | Palette opens; focus moves into the search input; dialog's `aria-label` spoken |
| 2 | Type a query | Same result-count/loading announcements as single-select, spoken from within the dialog |
| 3 | Select a result | Navigation occurs (if `meta.href` is set); dialog closes |
| 4 | Press `Escape` with no text and the listbox closed | Dialog closes; focus returns to whatever triggered it |
| 5 | Trigger the chord again while already open | Dialog closes (toggle behaviour) |

Record results (pass/fail per row, AT/browser combination, and any
notes) in the repository alongside the release they were run against —
this guide intentionally doesn't embed a stale set of results.
