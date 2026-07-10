---
status: ready
date: 2026-07-10
depends_on: [adr-001, adr-002, adr-004, adr-005]
---

# Spec 001: Portable single-select

Make the extracted ARCC `SearchableSelect` library-grade: a type-to-search,
pick-one combobox over an Ash resource, with no host-app couplings. This is
the foundation everything else builds on — mostly decoupling and hardening,
not new capability.

## Scope

- **Declarative Tier 1 config** ([ADR-001](../adrs/adr-001-two-tier-provider-architecture.md)):
  `resource`, `actor`, `tenant`, `search` (field list), `option_label`,
  `option_sublabel` (atom or 1-arity fun), `read_action`, `limit`, `sort`,
  base `filter`.
- **`Flicker.Provider` behaviour** for custom/federated sources, with
  `source={MyApp.Search.Global}` on the component. `search/2` and `fetch/2`
  required; `facets/0` and `render_option/2` optional no-ops for now.
- **`%Flicker.Result{value, label, sublabel, meta}`** and `Flicker.Query`
  structs.
- **Both selection modes** ([ADR-005](../adrs/adr-005-form-field-mode-owns-hidden-inputs.md)):
  form-field mode (hidden input + `_unused_` marker, ported from ARCC) and
  controlled mode (`on_select`). Optional AshPhoenix.Form `attach/2` adapter.
- **Theme system** ([ADR-002](../adrs/adr-002-rendering-via-slots-and-theme-map.md)):
  `Flicker.Theme` class-map, vanilla + Tailwind + daisyUI presets, `:option`
  slot override.
- **Query robustness**: debounce, `min_chars`, stale-result cancellation
  (drop responses for superseded keystrokes), loading and empty states,
  "keep typing to narrow" cap. `connected?/1` gating on all interactive
  controls.
- **JS packaging**: keyboard-nav hook shipped as a LiveView colocated hook;
  Igniter installer (`mix igniter.install flicker`) wires the hook, default
  theme config, and formatter imports.
- **Accessibility**: full WAI-ARIA combobox — `role`, `aria-expanded`,
  `aria-controls`, `aria-activedescendant`, announced result counts, focus
  management, labelled clear control.
- **Config**: `config :flicker, default_theme:, default_limit:,
  default_debounce:`.
- **Testing helper**: PhoenixTest `search_select/3` so consumers test at the
  user level.

## Non-goals

- Multi-select, chips, list values ([Spec 002](./spec-002-multi-select-chips.md)).
- Facets, `key:value` parsing, value autocomplete ([Spec 003](./spec-003-faceted-search.md)) —
  but `Flicker.Query` and the provider contract must not preclude them.
- Auto-deriving `search` fields from resource text attributes (open question
  in [DESIGN.md](../DESIGN.md); explicit-only for now).

## Design

Component is a `Phoenix.LiveComponent` (`use Phoenix.LiveComponent` — no
host web module, no `~p`, no heroicons assumption). Target usage:

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

Tier 1 compiles to an anonymous provider so search/fetch have one execution
path. Reads are `actor:`-scoped, policies filter
([ADR-004](../adrs/adr-004-authorization-via-actor-and-policies.md)).
Free-text matching is ilike over the `search` fields, with the strategy left
pluggable internally (trigram/full-text later).

Port from ARCC with renames: `SearchableSelect` → component,
`Search.{Source,Result}` → `Flicker.{Provider,Result}`, JS hook, PhoenixTest
helper. The `_unused_<field>` logic moves verbatim — it is proven.

## Acceptance criteria

- A resource + `search` fields is sufficient config — no module written, no
  options assign plumbed.
- Reads respect `actor`/policies: a record the actor can't read never
  appears in results and never resolves via `fetch`.
- In form mode: required-field error does not fire until the field is
  engaged; value survives a LiveSocket reconnect; the hidden input carries
  the selection into params.
- In controlled mode: no form inputs rendered; `on_select` fires with the
  `%Flicker.Result{}`.
- Typing before the socket connects cannot lose input (controls gated on
  `connected?/1`).
- A stale response (slower query for an earlier keystroke) never overwrites
  newer results.
- Keyboard: arrows navigate, Enter selects, Escape closes, focus management
  per WAI-ARIA combobox; axe (or equivalent) passes on the rendered markup.
- `mix igniter.install flicker` on a fresh Phoenix app yields a working
  select with zero manual wiring.
- A consumer test can drive selection with `search_select/3` alone.

## Open questions

- Colocated hook vs npm package — colocated assumed here; revisit if
  LiveView-version coupling bites (tracked in [DESIGN.md](../DESIGN.md)).
