---
status: shipped # draft | ready | in-progress | shipped
date: 2026-07-28
depends_on: [spec-003, spec-007, spec-012, spec-018, adr-002, adr-007, adr-009, adr-011, adr-013]
---

# Spec 019: Facet editors — the pop-out, the calendar, the dial, the switch, the set

[Spec 018](./spec-018-rich-facet-types.md) gave facets structure — ranges,
presets, bounds, closed sets, validation reasons — with no rendering.
[ADR-011](../adrs/adr-011-facet-editors-are-modal-subcontexts.md) decided what a
rich editor *is*: a modal sub-context that commits once and serialises back to
canonical token text. This spec builds them: the `Flicker.FacetEditor`
behaviour, the pop-out surface and its focus contract, and the four editors
Flicker ships — a **date/date-range calendar** with a presets rail, a **numeric
dial** (dual-thumb range slider), a **switch** for booleans, and a **set
editor** driven by one value source.

**Amended during implementation.** The set editor is *not* literally a nested
`Flicker.select`: controlled mode notifies via `send(self(), …)`, and `self()`
inside a `LiveComponent` is the host LiveView, so a nested select could never
return its selection to the editor containing it without host boilerplate. See
[ADR-011](../adrs/adr-011-facet-editors-are-modal-subcontexts.md)'s amendment
for what survives (`value_source/1` as the one definition of candidates) and
what is lost (inheriting the select's windowing).

The organising principle, and the thing that separates this from a widget
collection: **the editor is never the only way in.** Every value an editor can
produce can be typed, completed by typeahead, pasted, or restored from a URL,
because all four produce the same token text. The editor is the *fast, humane,
discoverable* path — never a gate.

## Scope

### `Flicker.FacetEditor` behaviour

```elixir
@callback render(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

# Canonical token text for a complete value (ADR-013: locale-invariant).
@callback serialise(value :: term(), facet :: Facet.t()) :: String.t()

# The editor's own state from an existing token — reopening a committed pill.
@callback parse(token_value :: String.t(), facet :: Facet.t()) ::
            {:ok, term()} | :error

# Is this value complete enough to commit? (ADR-011: atomic commit)
@callback complete?(value :: term(), facet :: Facet.t()) :: boolean()

# Optional: a one-line summary of the draft state, shown in the footer.
@callback draft_label(value :: term(), facet :: Facet.t(), opts :: keyword()) ::
            String.t() | nil

# Optional: does this editor need a pop-out at all? (ADR-011's switch case)
@callback modal?() :: boolean()
```

`modal?/0` defaults to `true`. `serialise/2` and `parse/2` are a round-trip
pair, and the property test that they compose to identity for every editor is
the load-bearing test of this spec.

Default type → editor mapping:

| Facet type | Editor | Modal? |
|---|---|---|
| `:date`, `:date_range`, `:datetime`, `:datetime_range` | `Flicker.FacetEditor.Calendar` | yes |
| `:number_range`, `:integer`/`:float` with `:bounds` | `Flicker.FacetEditor.Dial` | yes |
| `:duration` | `Flicker.FacetEditor.Dial` (duration mode) | yes |
| `:boolean` | `Flicker.FacetEditor.Switch` | **no** — inline in the pill |
| `:enum`, relationship | `Flicker.FacetEditor.Set` | yes |
| `:string`, unbounded numerics | none — type into the input | — |

`facet.editor` overrides any row. A host module implementing the behaviour is
indistinguishable from a built-in.

### Opening, committing, cancelling

**Four ways to open**, all landing in the same state:

1. Choosing a **facet-key suggestion** (`status:`) opens that facet's editor
   immediately, rather than inserting text and waiting. This is the single
   biggest discoverability win available: the user learns the rich control
   exists by doing the thing they were already doing.
2. Clicking a **committed pill** (Spec 012) reopens the editor via `parse/2`,
   pre-filled.
3. `↓` or `Ctrl`/`⌘`+`Space` while the cursor context is `{:value, facet, _}`
   (Spec 018 also reports which range endpoint / list element the caret is in,
   so the editor opens focused on the right control).
4. Clicking the facet-type affordance in the pill's trailing edge — a calendar
   glyph, a slider glyph — which is also what signals "there's more here".

**Commit** happens exactly once, when `complete?/2` returns true and the user
confirms (`Enter`, a click on the final day, a preset row, a switch toggle). It
splices canonical text via `FacetSuggest.replace_current_token/3`, closes the
pop-out, restores focus and caret, and fires **one** `on_change`.

**Cancel** (`Escape`, click-outside, `Tab` past the last control) discards the
draft, restores the token to exactly its prior text, and fires nothing.

**While open, nothing dispatches.** Paging months, dragging a thumb, hovering a
range — none of it touches the server-side query.

### The pop-out surface

- `role="dialog"`, `aria-modal="true"`, labelled by the facet's `:label`.
- Focus moves in on open, is trapped while open, and is restored to the input
  with the caret exactly where it was on close (both commit and cancel).
- The main picker's keyboard model is **suspended** (ADR-011): `↑`/`↓`, `Enter`,
  `Home`/`End` belong to the editor.
- Positioned against the pill or the caret, flipped when it would overflow the
  viewport, and **never clipped by the picker's own scroll container**.
- On viewports below the theme's small breakpoint it renders as a **bottom
  sheet**, full-width, with a visible header and a Done control — a 252px-wide
  calendar in a dropdown is unusable on a phone.
- Respects `prefers-reduced-motion` (no slide/fade), `prefers-contrast`, and
  forced-colors mode.
- Announces on open ("Created date editor, dialog") and on commit ("Created is
  Jun 18 to Jul 12") per Spec 007.

### `Flicker.FacetEditor.Calendar`

Ported in *behaviour* from a known-good design; the implementation is
LiveView + a colocated hook (ADR-007), no JS dependency.

Layout: a **presets rail** on the left, one or two **month grids** on the right,
a **footer** carrying the draft state and a cancel control. `months` defaults to
2 for range types and 1 for single-date types.

- Each preset row shows its label and, right-aligned and dimmed, its **resolved
  range** — so `Last 30 days` visibly means `Jun 29 – Jul 28`. This is the
  detail that makes presets trustworthy rather than mysterious.
- `:suggested` presets appear first under a `Suggested` heading, the rest under
  `More` (Spec 018's fields).
- Range selection is two clicks. Between them, the grid shows a **live hover
  band** from the draft start to the hovered day, and the footer reads
  `Jun 18, 2026 → pick an end date`. Picking a day before the draft start
  swaps the endpoints rather than erroring.
- Today is ringed, not filled. The selected endpoints are filled; the interior
  band is tinted; the half-cells at each end are gradient-clipped so the band
  reads as continuous across the boundary.
- Month names, weekday initials, and **the locale's first day of week** come
  from `localize` (ADR-013), falling back to English/Monday.
- Datetime range types add a time field per endpoint, UTC, with the timezone
  stated in the footer so `00:00–23:59` is never ambiguous.

Keyboard (a full, non-negotiable map — a calendar you can't drive from the
keyboard is not shippable):

| Key | Action |
|---|---|
| `←`/`→`/`↑`/`↓` | ±1 day, ±1 week |
| `PageUp`/`PageDown` | ±1 month |
| `Shift`+`PageUp`/`PageDown` | ±1 year |
| `Home`/`End` | first/last day of the week |
| `Enter`/`Space` | set draft start, then commit the range |
| `Backspace` | clear the draft start |
| `Tab` | into the presets rail, then the footer |
| `↑`/`↓` in the rail | move between presets; `Enter` commits |
| `Escape` | cancel |

`aria-activedescendant` tracks the focused day; the grid is a `role="grid"` with
`aria-selected` on endpoints and `aria-describedby` announcing the draft state.

### `Flicker.FacetEditor.Dial`

The "from this number to that number" control, and the reason Spec 018 derives
`:bounds` from Ash constraints.

- **Bounded** (`:bounds` present) → a dual-thumb slider with a filled track
  between the thumbs, plus a **paired numeric input per endpoint** for
  precision. The slider is for feel, the inputs are for exactness; they are two
  views of one value and stay in sync.
- **Unbounded** → the numeric inputs alone, no invented endpoints.
- **Duration mode** → thumb steps snap to human units (15m, 30m, 1h) and the
  label formats via `Localize.Duration`.
- Thumbs clamp rather than cross; the lower can equal the upper.
- An endpoint left blank is an **open bound**, serialising to `10..` or `..50`
  (Spec 018) — a slider that cannot express "over 100" is a worse control than
  two text boxes, so this must be reachable from both views.
- `:step` defaults to a sane derivation from the range span, overridable.
- Values format through `Facet.Format` (locale digits, grouping, currency where
  the facet declares one) while serialising canonically.

Keyboard: each thumb is a `role="slider"` with `aria-valuemin/max/now/text`
(`aria-valuetext` carries the *formatted* value, so a screen reader says "fifty
dollars", not "50"). `←`/`→` ±step, `PageUp`/`PageDown` ±10 steps, `Home`/`End`
to the bound, `Tab` between thumbs and into the inputs, `Enter` commits.

Touch: thumbs get a ≥44px hit target regardless of visual size, and dragging one
never scrolls the sheet.

### `Flicker.FacetEditor.Switch`

The degenerate case, per ADR-011: `role="switch"`, `aria-checked`, `Space`
toggles, **commits on toggle**, no pop-out, rendered inline in the pill. "Not
filtered at all" remains the pill's remove control, which keeps the switch
honestly binary. For a nullable boolean the facet may opt into a third
`Unknown` state, which serialises as `is_nil`.

### `Flicker.FacetEditor.Set`

A nested `Flicker.select` (ADR-011) with `source: Facet.value_source(facet)`
(Spec 018), `multiple: facet.multiple?`, controlled, **no facets of its own** —
the leaf rule. Inherits Spec 002's chips, Spec 013's `:selected` slot, Spec 017's
value colours, Spec 010's windowing for large sets, and every future
`Flicker.select` improvement for free.

Additions specific to editing:
- Multi mode commits the whole selection on `Enter`/Done as one `:in` token, not
  per-toggle.
- `Select all matching` when a search is active and the provider reports a count.
- Selected values sort to the top on reopen, so a re-edit shows what's on.

### Theme parts (ADR-002)

New parts, each covered by all three presets and enforced by the existing
`Flicker.ThemeTest` struct-key sweep:

`:facet_editor`, `:facet_editor_header`, `:facet_editor_body`,
`:facet_editor_footer`, `:facet_editor_sheet`, `:preset_rail`, `:preset_group_label`,
`:preset_row`, `:preset_row_selected`, `:preset_row_range`, `:calendar`,
`:calendar_nav`, `:calendar_nav_button`, `:calendar_month_label`,
`:calendar_weekday`, `:calendar_grid`, `:calendar_day`, `:calendar_day_today`,
`:calendar_day_selected`, `:calendar_day_in_range`, `:calendar_day_edge`,
`:calendar_day_disabled`, `:dial`, `:dial_track`, `:dial_fill`, `:dial_thumb`,
`:dial_input`, `:dial_value_label`, `:switch`, `:switch_thumb`, `:switch_on`,
`:editor_error`.

## Non-goals

- **No new grammar.** Every token an editor emits is already parseable by Spec
  018. If an editor wants to express something the grammar can't, the grammar
  changes first — that's ADR-011's design gate, not a workaround.
- **No localised parsing** (ADR-013). Editors accept locale-native *input* and
  normalise on commit; the wire form stays canonical.
- **No timezone picker.** UTC, stated in the footer (Spec 018's scope cut).
- **No facet value counts.** The `12` beside `Active` is real faceted search and
  needs a provider callback; separate spec.
- **No query dispatch policy.** When the query fires is Spec 020.
- **No drag-to-reorder of pills, no saved views, no query history.** Later, if at
  all.

## Design

### State ownership

The editor's draft lives in the owning component's assigns under a single
`:facet_editor` key — `%{facet: facet, editor: module, value: term(), origin:
{token_start, token_stop}}` — and is `nil` when closed. Nothing else in the
component branches on editor state; there is exactly one open editor at a time
and one place to look for it. `:origin` is why cancel can restore the token
byte-for-byte and commit can splice without re-tokenising.

`value` is the editor's own shape (a `{Date, Date}` pair, a `{min, max}` tuple, a
list of selected values). It becomes token text only at `serialise/2`, and never
enters `Flicker.Query`.

### The round-trip property

For every editor, every facet of a compatible type, and every value that
`complete?/2` accepts:

```elixir
value |> editor.serialise(facet) |> then(&editor.parse(&1, facet)) == {:ok, value}
```

and, crucially, the serialised text parses to the same filter through the real
parser:

```elixir
Query.parse("#{facet.key}:#{editor.serialise(value, facet)}", [facet]).facets != []
```

The second is what stops an editor drifting from the grammar. Both are property
tests over generated values, and they run without a browser.

### Progressive enhancement

The editors are LiveView-rendered with a colocated hook (ADR-007) for caret
restore, focus trap, hover-band tracking, and pointer drag. Without JS: the
calendar's day buttons are real buttons that submit a pick, the dial's numeric
inputs are real inputs, the switch is a real checkbox. Degraded, not broken —
hover bands and drag are the only casualties.

### Latency

Opening an editor for a `:enum`/`:boolean`/`:date`/numeric facet needs **no
server round-trip** to render — every value it needs is already in the facet
struct. Only the relationship `Set` editor queries, and it opens immediately with
its listing pending. This matters: an editor that stutters on open feels worse
than typing, and typing is the thing it's competing with.

## Acceptance criteria

Framework:

- [ ] `serialise`/`parse` round-trip as identity for every built-in editor, as a
      property test over generated values.
- [ ] Every editor's serialised output parses to a non-empty `:facets` through
      `Query.parse/2` with the same facet registry.
- [ ] A host module implementing `Flicker.FacetEditor` and set via
      `facets: [x: [editor: Mod]]` is used in place of the built-in.
- [ ] `complete?/2` false means no commit is possible by any route (`Enter`,
      click, Done).
- [ ] No `on_change` fires between opening and committing an editor — asserted by
      counting emissions across a full range selection.
- [ ] Cancel restores the input text and caret byte-for-byte.
- [ ] Committing splices only the origin token; free text and other facet tokens
      either side survive untouched.
- [ ] At most one editor is open at a time; opening a second closes the first as a
      cancel.

Calendar:

- [ ] Two clicks commit a range; clicking earlier-then-later and
      later-then-earlier produce the same range.
- [ ] Each preset row displays the range it resolves to, and committing it emits
      the preset **id**, not the resolved dates.
- [ ] Every key in the table does what the table says, verified in the Spec 007
      browser suite.
- [ ] Month names, weekday order, and first day of week change with the locale
      and fall back to English/Monday without `localize`.
- [ ] A single-date facet renders one month and commits in one click.
- [ ] Reopening a committed pill restores the exact range or preset.

Dial:

- [ ] A facet with `bounds: %{min: 0, max: 500}` renders two thumbs at the
      committed endpoints; one without bounds renders inputs only.
- [ ] Thumb and numeric input stay in sync in both directions.
- [ ] Clearing an endpoint commits an open bound (`10..` / `..50`).
- [ ] Thumbs clamp instead of crossing.
- [ ] `aria-valuetext` carries the *formatted* value, not the raw number.

Switch / Set:

- [ ] The switch commits on toggle with no pop-out, and remove clears the facet
      entirely (distinct from `false`).
- [ ] The set editor renders a `Flicker.select` with the facet's `value_source`,
      and that select has no facets of its own (asserted, not documented).
- [ ] Multi mode commits one `:in` token for the whole selection.
- [ ] An enum set editor opens with zero server round-trips.

Accessibility (Spec 007 suite):

- [ ] axe-core clean on every editor, open and mid-draft, light and dark.
- [ ] Focus enters on open, is trapped, and returns to the caret on close.
- [ ] Open, draft, commit, and cancel are each announced.
- [ ] The whole flow — open, select a range, commit, reopen, cancel — is
      completable with the keyboard alone, and with a screen reader alone.
- [ ] Every editor is usable at 200% zoom and at a 320px viewport width.
- [ ] `prefers-reduced-motion` suppresses all transitions.

## Open questions

None blocking.

- **Presets for numeric facets.** A price dial might want `Under $50`,
  `$50–200`. The preset machinery is type-agnostic in Spec 018; worth exposing
  for numbers once the calendar's rail has proven the interaction.
- **Non-linear dials.** A `0..1_000_000` range is unusable linearly. A log scale
  is the fix but distorts the relationship between thumb position and value in a
  way that needs care; deferred until a real facet needs it.
- **Pill overflow.** Six committed facets plus a localised interval label
  overflows a single-line input. Wrapping is the obvious answer; an
  `+3 more` collapse might be better on narrow viewports. Spec 012's call.
- **Recently used values.** Surfacing a user's last-used values at the top of a
  set editor is probably the single highest-value addition after this ships, and
  needs a storage decision (host-provided callback vs. Flicker-owned).
