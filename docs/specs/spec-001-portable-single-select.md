---
status: shipped
date: 2026-07-10
depends_on: [spec-004, adr-001, adr-002, adr-004, adr-005, adr-007, adr-009]
---

# Spec 001: Portable single-select

Make the extracted origin `SearchableSelect` library-grade: a type-to-search,
pick-one combobox over an Ash resource, with no host-app couplings. Builds
on the provider contract from
[Spec 004](./spec-004-provider-contract.md) — this spec is the component:
rendering, state, keyboard, forms.

## Scope

- **Declarative Tier 1 config** ([ADR-001](../adrs/adr-001-two-tier-provider-architecture.md)):
  `resource`, `actor`, `tenant`, `search` (field list), `option_label`,
  `option_sublabel` (atom or 1-arity fun), `read_action`, `limit`, `sort`,
  base `filter` — compiled at mount to the `AshResource` provider from
  Spec 004. Custom providers via `source={MyApp.Search.Global}`.
- **Both selection modes** ([ADR-005](../adrs/adr-005-form-field-mode-owns-hidden-inputs.md)):
  form-field mode (hidden input + `_unused_` marker, ported from the
  origin app) and controlled mode (`on_select`). Form-field mode can also
  set `on_select` to notify its host after a selection changes, for dependent
  fields that must refresh before form submission. Optional AshPhoenix.Form
  `attach/2` adapter.
- **Theme system** ([ADR-002](../adrs/adr-002-rendering-via-slots-and-theme-map.md)):
  `Flicker.Theme` class-map, vanilla + Tailwind + daisyUI presets, `:option`
  slot override.
- **Query robustness**: debounce, `min_chars`, stale-result cancellation
  (drop responses for superseded keystrokes), loading and empty states,
  "keep typing to narrow" cap. `connected?/1` gating on all interactive
  controls.
- **JS packaging**: keyboard-nav hook shipped as a colocated hook
  ([ADR-007](../adrs/adr-007-colocated-js-hook.md)); Igniter installer
  (`mix igniter.install flicker`) wires the `phoenix-colocated/flicker`
  import, default theme config, and formatter imports.
- **Accessibility**: WAI-ARIA editable-combobox semantics — `role`,
  `aria-expanded`, `aria-controls`, `aria-activedescendant`,
  `aria-autocomplete="list"` — plus the live-region announcement plumbing.
  The full bar and AT verification are
  [Spec 007](./spec-007-screen-reader-support.md); this spec makes the
  markup correct and every state in the keyboard map reachable.
- **All user-facing strings** (visible and announced) through the messages
  module ([ADR-009](../adrs/adr-009-messages-module-for-user-facing-text.md))
  from the first template — no inline literals.
- **Config**: `config :flicker, default_theme:, default_limit:,
  default_debounce:`.
- **Testing helper**: PhoenixTest `search_select/3` so consumers test at the
  user level.

## Non-goals

- The provider behaviour, structs, and `AshResource`/in-memory providers —
  built first in [Spec 004](./spec-004-provider-contract.md).
- Multi-select, chips, list values ([Spec 002](./spec-002-multi-select-chips.md)).
- Facets, `key:value` parsing, value autocomplete ([Spec 003](./spec-003-faceted-search.md)) —
  but `Flicker.Query` and the provider contract must not preclude them.
- Auto-deriving `search` fields from resource text attributes (open question
  in [DESIGN.md](../DESIGN.md); explicit-only for now).

## Design

The public face is a **function component** (`Flicker.select/1`) declared
with `attr`/`slot` so hosts get compile-time validation and HEEx docs; it
immediately renders the internal `Phoenix.LiveComponent` that owns search
state. Hosts never address the LiveComponent directly — its module name,
assigns, and events are internal. No host web module, no `~p`, no heroicons
assumption. Target usage:

```heex
<Flicker.select
  field={f[:client_id]}
  resource={MyApp.Client}
  actor={@current_user}
  search={[:first_name, :last_name, :uci_number]}
  option_label={:full_name}
  option_sublabel={&"#{&1.uci_number} · #{&1.city}"}
  read_action={:search}
  limit={20}
/>
```

All data access goes through the Spec 004 provider boundary — one execution
path, and component tests run against the in-memory provider with no Ash
data layer. Reads are `actor:`-scoped, policies filter
([ADR-004](../adrs/adr-004-authorization-via-actor-and-policies.md)).

Ported from the origin implementation: the component event flow, the JS
hook, and the PhoenixTest helper. The `_unused_<field>` logic moved
verbatim — it was proven there.

### Keyboard interaction — the full map

Follows the WAI-ARIA APG editable-combobox pattern: DOM focus stays in the
text input at all times; option highlight moves via
`aria-activedescendant`. Every transition below has a defined announcement
(keys per [ADR-009](../adrs/adr-009-messages-module-for-user-facing-text.md);
verification in [Spec 007](./spec-007-screen-reader-support.md)).

| State | Key | Behaviour |
|---|---|---|
| closed, input focused | `ArrowDown` / `Alt+ArrowDown` | open listbox; `ArrowDown` also makes the first option active |
| closed, input focused | printable character | open listbox and search (subject to `min_chars`/debounce) |
| open | `ArrowDown` / `ArrowUp` | move active option down/up; **no wrap** — stops at last/first |
| open | `Enter` | select the active option, close, focus stays in input; no active option → no-op (never submits the surrounding form while open) |
| open | `Escape` | close the listbox, keep input text; a second `Escape` (closed, text present) clears the input |
| open | `Tab` | close without selecting; focus moves per natural tab order |
| open | `Home` / `End` | **not captured** — native text-caret behaviour in the input |
| open, results updated | — | active option resets to none (or first, configurable); count announced |
| any | click/focus outside | close without selecting |
| single, selection present | `Backspace`/clear control | clear the selection (returns to searchable state) |
| multi, input empty | `Backspace` | remove last chip ([Spec 002](./spec-002-multi-select-chips.md)) |

`Enter`-while-open must `preventDefault` so a combobox inside a form never
accidentally submits it — regression-tested, it's a classic combobox bug.

## Acceptance criteria

- A resource + `search` fields is sufficient config — no module written, no
  options assign plumbed.
- Reads respect `actor`/policies: a record the actor can't read never
  appears in results and never resolves via `fetch`.
- In form mode: required-field error does not fire until the field is
  engaged; value survives a LiveSocket reconnect; the hidden input carries
  the selection into params.
- In controlled mode: no form inputs rendered; `on_select` fires with the
  `%Flicker.Result{}`. In form mode, an optional `on_select` fires with the
  same result while Flicker continues to own the hidden field inputs.
- Typing before the socket connects cannot lose input (controls gated on
  `connected?/1`).
- A stale response (slower query for an earlier keystroke) never overwrites
  newer results.
- Every row of the keyboard map behaves as specified, covered by tests;
  `Enter` while the listbox is open never submits the surrounding form.
- axe reports zero violations on the rendered markup (full AT verification
  is [Spec 007](./spec-007-screen-reader-support.md)).
- No user-facing string literal appears in templates — all text resolves
  through the messages module.
- `mix igniter.install flicker` on a fresh Phoenix app yields a working
  select with zero manual wiring.
- A consumer test can drive selection with `search_select/3` alone.

## Open questions

- ~~Colocated hook vs npm package~~ — resolved: colocated
  ([ADR-007](../adrs/adr-007-colocated-js-hook.md)).
- After results update, does the active option reset to none or first?
  (Map above says configurable; pick a default during implementation and
  record it.)
