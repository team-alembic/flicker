---
status: current
date: 2026-07-10
---

# Flicker — design overview

The north-star document: what Flicker is, why it exists, and how the work is
sequenced. Decisions live in [ADRs](./adrs/README.md); implementable detail
lives in [specs](./specs/README.md) — this file links rather than restates.

**Origin:** extracted from `ArccWeb.Components.SearchableSelect` +
`ArccWeb.Search.*` built for ARCC's client/worker pickers (ARCC PR #462).
ARCC becomes Flicker's first consumer and proving ground.

## What it is

Flicker is a searchable select / combobox / faceted-search component for
Phoenix LiveView, built **Ash-first** — in the same spirit as Cinder is for
tables. Where Cinder renders and queries a collection, Flicker searches for
and selects records. Four capabilities:

1. **Search** — type-to-filter over an Ash resource with configurable read
   action, search fields/strategy, limit, sort, base filter, tenant, actor.
2. **Single select** — pick one record; integrates with `<.form>` or runs
   controlled.
3. **Multi-select** — pick many, rendered as removable chips.
4. **Faceted filtering** — Datadog-style
   `status:active worker:"Casey Nguyen" after:7d free text`, where each
   facet maps to an Ash filter and facet values autocomplete from the type
   system.

## Why it should exist (and when it shouldn't)

`LiveSelect` already does single/multi search-select for Phoenix. Flicker
exists for the Ash-native angle: it reads directly off resources (no options
plumbing), authorises via `actor:` + policies, derives facet behaviour from
the Ash type system, and installs via Igniter. **If it isn't materially more
Ash-integrated than LiveSelect, it shouldn't ship.**

## Naming

**Flicker** — a flame flickers, and you *flick through* results as you type;
the fire connotation keeps it in the Ash family (`Spark`, `Igniter`,
`Cinder`). Verified free on Hex (2026-07-10). Rejected: **Flint** (taken,
uncomfortably adjacent Ecto lib), **Wick** (taken), **Lantern** (taken, too
close to this space), Ash-ecosystem names. Free alternates in reserve:
`Ignis`, `Pyre`, `Tinder`.

## Sequencing

Build in this order — each phase is a spec:

0. **[Spec 004 — Provider contract](./specs/spec-004-provider-contract.md)**:
   the `Flicker.Provider` behaviour, `Result`/`Query` structs, built-in
   `AshResource` provider, and the `ash`-optional boundary
   ([ADR-006](./adrs/adr-006-core-depends-only-on-provider.md)). Pure
   Elixir, testable without LiveView — built first.
1. **[Spec 001 — Portable single-select](./specs/spec-001-portable-single-select.md)**:
   decouple from the host app, theme system, resource-first config, form +
   controlled modes, shipped hook + Igniter installer. Mostly "make the
   current component library-grade."
2. **[Spec 002 — Multi-select + chips](./specs/spec-002-multi-select-chips.md)**:
   list value, array inputs, batch `fetch/2`, chip UX.
3. **[Spec 003 — Faceted search](./specs/spec-003-faceted-search.md)**:
   parser, facet registry, type-derived value autocomplete, cursor-context
   state machine. Highest risk and highest differentiation, so it's built
   last on a proven base — and its state machine gets prototyped first.

Alongside from Spec 001 onward:
**[Spec 005 — dev playground](./specs/spec-005-dev-playground.md)** — an
in-repo `dev/` Phoenix app (à la `ash_authentication_phoenix`) with seeded
ETS-backed resources; every spec adds its page as part of its definition of
done.

## What changes from the ARCC code

| Today (ARCC) | Flicker |
|---|---|
| `Search.Source` required | resource+fields default; `Flicker.Provider` optional ([ADR-001](./adrs/adr-001-two-tier-provider-architecture.md)) |
| `use ArccWeb, :live_component` | `use Phoenix.LiveComponent` + `Flicker.Theme` |
| daisyUI classes hardcoded | swappable theme presets ([ADR-002](./adrs/adr-002-rendering-via-slots-and-theme-map.md)) |
| `Result` with `type`/`icon`/`bg_class` | generic `%Flicker.Result{}` + `:option` slot |
| single value | single **and** list + chips + list `fetch/2` ([ADR-003](./adrs/adr-003-fetch-takes-a-list.md)) |
| plain ilike over fields | pluggable strategy + faceted parser |
| `read_permission/0` gate | `actor:`/policy-scoped reads ([ADR-004](./adrs/adr-004-authorization-via-actor-and-policies.md)) |
| hook lives in app JS | shipped hook + Igniter installer |
| free-text query only | `key:value` parser + type-derived facet autocomplete |

## Extraction plan

1. ~~Stand up the new repo with standard Ash-lib scaffolding~~ (done — this
   repo).
2. Move `SearchableSelect` + `Search.{Source,Result,Sources.*}` + the JS
   hook + the PhoenixTest helper from ARCC, renaming to `Flicker.*` and
   severing `ArccWeb`/`ArccUI`/daisyUI couplings (= Spec 001).
3. Add Flicker as a dep back into ARCC and reimplement the client/worker/
   authorization pickers on top of it.

## Component surface

Three public components — one axis each, all thin presentations over the
same core (provider boundary, keyboard map, theme, messages):

| Component | Question it answers | Value produced | Specs |
|---|---|---|---|
| `Flicker.select` | "which record(s)?" | selection → form params / `on_select`; `multiple` switches single/multi — there is **no** separate `multi_select` component | [001](./specs/spec-001-portable-single-select.md), [002](./specs/spec-002-multi-select-chips.md) |
| `Flicker.search` | "which subset?" | `%Flicker.Query{}` / composed Ash filter → `on_change`; no selection semantics — the Datadog-style filter bar that drives a table, stream, or list | [003](./specs/spec-003-faceted-search.md) |
| `Flicker.palette` | "take me there" | navigation via `meta.href` (⌘K overlay) | [008](./specs/spec-008-command-palette.md) |

If a new capability doesn't fit one of these three questions, it's a new
component (and a spec), not a mode flag on an existing one.

## Public API & stability

What semver protects. Anything listed here is public contract: breaking it
is a major bump post-1.0 (pre-1.0, a `0.x` minor with a loud CHANGELOG
entry). Everything *not* listed is internal — change freely.

**Public:**

- `Flicker.select/1`, `Flicker.search/1`, `Flicker.palette/1`: attr and
  slot names, types, defaults (see [Component surface](#component-surface)).
- The `Flicker.Provider` behaviour: callback signatures and documented
  `opts` keys.
- `%Flicker.Result{}`, `%Flicker.Query{}`, `%Flicker.Facet{}` struct fields.
- `Flicker.Theme`: part names in the class map, and preset names.
- `Flicker.Messages`: the callback and the message-key list
  ([ADR-009](./adrs/adr-009-messages-module-for-user-facing-text.md)).
- Testing helpers (`search_select/3` and variants).
- Config keys under `config :flicker, ...` and the Igniter task name.
- Version floors, lowered never / raised per
  [ADR-008](./adrs/adr-008-version-floors.md).

**Internal (explicitly):** the LiveComponent module, its assigns and
events; hook internals and JS event payloads; `Flicker.Providers.AshResource`'s
private options; DOM structure beyond documented theme parts;
`Result.meta` contents for built-in providers (hosts own `meta` for their
own providers).

## Open questions

Cross-cutting ones live here; spec-local ones live in each spec.

- Should Tier 1 auto-derive `search` fields from the resource's text
  attributes, or always require them explicitly?
- ~~Does Flicker own a global-search-bar variant?~~ — resolved: yes, as
  the `Flicker.palette` ⌘K command-palette experience
  ([Spec 008](./specs/spec-008-command-palette.md)) — thin composition
  over the core, DocSearch/cmdk prior art.
