---
status: shipped
date: 2026-07-10
depends_on: [spec-001, spec-002, adr-001, adr-006]
---

# Spec 003: Faceted / scoped filtering

Datadog-style `status:active worker:"Casey Nguyen" after:7d free text`, where
each facet maps to an Ash filter and facet-value autocomplete is derived from
the Ash type system. The differentiating feature — highest risk, built last
on a proven base. A mini-project: expect this spec to split into sub-specs
once the prototype lands.

This spec has **two deliverables**, sharing the parser, registry, and
cursor-context machinery:

1. **`Flicker.search/1`** — a standalone public component (see the
   component-surface table in [DESIGN.md](../DESIGN.md#component-surface)):
   a faceted search input with *no selection semantics* that emits the
   composed `%Flicker.Query{}` / Ash filter via `on_change`. The Datadog
   filter bar as a component — the host feeds the filter to a Cinder
   table, a stream, or its own list. This is faceted search's most
   valuable form and drives the Cinder interop story.
2. **Facets inside `Flicker.select` / `Flicker.palette`** — the same input
   machinery embedded where the result of the narrowed search is a
   selection or navigation.

## Scope

Three shared pieces:

- **Facet registry → Ash filter.** A facet maps a key to an Ash filter
  target — attribute, relationship path, aggregate, or expression calc (the
  same targets Cinder columns allow):

  ```elixir
  facets: [
    status:        [type: :enum],
    worker:        [path: [:worker, :full_name]],
    city:          [attribute: :city],
    after:         [attribute: :inserted_at, op: :>=],
    session_count: [aggregate: :sessions_count, op: :>]
  ]
  ```

- **Query parser.** Tokenises input into free text + facet tokens, honouring
  quotes and operators, producing a `Flicker.Query`:

  ```
  status:active worker:"Casey Nguyen" after:7d visit notes
  => %Flicker.Query{
       text: "visit notes",
       facets: [{:status, :eq, :active}, {:worker, :eq, "…id…"}, {:after, :gte, ~D[…]}]
     }
  ```

  Free text hits the `search` fields; facets compose into `Ash.Query.filter`
  — distinct facets AND, repeated same-facet OR.

- **Type-derived value autocomplete.** `facets: [:status, :worker,
  :inserted_at, :active?]` is enough — the attribute's type drives behaviour:

  | Attribute type | Facet behaviour |
  |---|---|
  | `Ash.Type.Enum` | value picklist with the enum's own labels; invalid values rejected with a hint |
  | `:boolean` | `true` / `false` |
  | `:utc_datetime` / `:date` | date picker + relative (`after:7d`), operators `>=` `<` |
  | `:integer` / `:decimal` | numeric, operators `>=` `<` `!=` |
  | `belongs_to` / `has_*` | **recursive Flicker** — nested actor-scoped record search over the related resource; picking one inserts `worker:<id>` displayed as the record's label |
  | aggregate / expr calc | numeric/boolean filter as the calc dictates |
  | `:string` | free ilike, no picklist |

## Non-goals (initially)

- Grouping and explicit boolean syntax (`status:(active OR pending)`,
  negation `-status:active`) — grammar scope is an open question below.
- Saved/named filters, URL serialisation of queries.

## Design

The filtering is free (Ash does it). The engineering is the **cursor-context
state machine**: at each cursor position the dropdown must know whether the
user is typing a facet key (`stat` → suggest `status:`), a facet value
(`status:` → enum picklist / nested search), or free text, and switch its
result source and keyboard behaviour accordingly.

**Prototype the state machine first, in isolation, before wiring facets into
the query path.** It defines the component; if it doesn't feel right, the
rest doesn't matter. Model it as an explicit state (`{:key, prefix}`,
`{:value, facet, prefix}`, `:text`) derived purely from (input string, cursor
position) so it is unit-testable without a browser.

Parser is a pure function `(input, facet_config) -> Flicker.Query` —
property-test it hard (quotes, escapes, adjacent tokens, unknown keys,
malformed operators degrade to free text rather than erroring).

Enum labels come from the type's own introspection, so facet rendering
cannot drift from form rendering elsewhere in the host app.

## Acceptance criteria (draft)

- Each row of the type table above has a working end-to-end example in the
  dev/test app.
- Distinct facets AND; repeated same-facet OR — verified against generated
  Ash filters, not just UI behaviour.
- Unknown facet keys and malformed values degrade to free text; the input
  never hard-errors on arbitrary typing.
- The relationship facet's nested search is actor-scoped (a worker the actor
  can't read can't be selected as a facet value).
- The state machine correctly classifies key/value/text context at every
  cursor position, including mid-token edits — covered by unit tests on the
  pure function.

## Open questions — resolved

- **Facet grammar scope**: resolved to the minimum in [Non-goals](#non-goals-initially)
  — no grouping, no explicit `OR`/`AND` syntax, no negation in v1. Distinct
  facet keys AND; repeated instances of the same key OR (`Flicker.Query.to_filter/2`).
  Extend by demand once a real use case needs it, as its own follow-up spec
  rather than growing this parser in place.
- **Global-search-bar variant**: out of scope here — it's
  [Spec 008 (`Flicker.palette`)](./spec-008-command-palette.md)'s concern,
  not `Flicker.search`'s.
- **Relative-date grammar**: shipped as the fixed set implemented in
  `Flicker.Query.cast_relative_date/1` — `<n>d` / `<n>w` / `<n>m` (30 days)
  / `<n>y` (365 days). Pluggable relative-date units are a follow-up, not
  needed by any current consumer.

## Implementation notes (v1 scope cuts)

Both deliverables ship on the shared parser/registry/cursor-context
machinery above (`Flicker.Query`, `Flicker.Facet`,
`Flicker.Providers.AshResource.facets/1`, `Flicker.CursorContext`,
`Flicker.FacetSuggest`). Both v1 scope cuts below have since been lifted —
neither scope cut remains open:

- **Resolved:** cursor tracking no longer assumes the caret sits at the
  end of the typed text. Both components' colocated hooks
  (`Flicker.Components.Search`'s `.FlickerSearchNav`,
  `Flicker.Components.Select`'s `.Nav`, ADR-007) report the input's real
  `selectionStart` on every keyup/click/select: `keyup` sets a
  `phx-value-cursor` attribute on the input directly (synchronously,
  before the event bubbles to LiveView's own delegated `phx-keyup`
  listener) so the existing debounced `"query"` push carries the matching
  cursor position for that same keystroke; `click`/`select` (no typed
  value changing, nothing to debounce) push a lightweight `"cursor"`
  event immediately. `Flicker.CursorContext.parse_selection_start/1`
  parses the raw payload and `Flicker.CursorContext.from_utf16_offset/2`
  converts the browser's UTF-16 code-unit offset to the codepoint offset
  `classify/3` expects; `Flicker.FacetSuggest.classify/3` does both steps
  for a caller. A cursor moved back into an already-typed token now
  classifies right there, not "at the end" — `Flicker.FacetSuggest.replace_current_token/3`
  completes that token in place too, preserving whatever free text or
  other facet tokens follow it, rather than clobbering them. `cursor`
  defaults to (and an explicit `nil` falls back to) end-of-text — the
  dead-render / very-first-event case, before the hook has reported a
  position yet, and the case right after either component sets the typed
  text itself (a chosen suggestion, `clear`, `escape`), since the browser
  resets the caret to the end of the input's value once that happens.
- **Resolved:** `facets` on `Flicker.select/1` now ANDs the parsed facet
  filter into the provider's own record query, not just the autocomplete UX
  and the free-text portion of the search. While the cursor is in
  facet-key/value position the listbox still shows key/value suggestions
  instead of records (picking one edits the typed text); once back in
  free-text position, `Flicker.Components.Select` passes the *full* parsed
  `Flicker.Query` (`.text` *and* `.facets`) to `Provider.run_search/3` —
  `Flicker.Providers.AshResource.search/2` composes `Flicker.Query.to_filter/2`
  into its Ash query alongside the free-text match, scoping *which records*
  are offered before that match runs. A provider decides for itself how to
  honour `query.facets` (`c:Flicker.Provider.search/2`'s doc): `AshResource`
  filters by them; `Flicker.Providers.Static` has no type system to derive
  facet filtering from and documents that it matches text only, ignoring
  `query.facets` entirely. `Flicker.search/1` never had this gap — it never
  lists records itself, it only emits the filter for the host to apply.

Acceptance criteria coverage: each type-table row has an end-to-end test
against `Dev.Music`/a purpose-built fixture (`Flicker.Providers.AshResourceFacetsTest`,
`Flicker.SearchTest`); distinct-AND/repeated-OR is asserted against the
generated Ash filter (`Flicker.QueryAshFilterTest`, `Flicker.SearchTest`);
unknown keys/malformed values degrade to free text without erroring
(`Flicker.QueryTest`, `Flicker.QueryPropertyTest`, `Flicker.SearchTest`);
the nested relationship-facet search is actor-scoped
(`Flicker.SearchTest`'s "nested relationship-facet search is actor-scoped"
describe block, against `Flicker.Test.FacetGenre`'s policy); the
cursor-context state machine is covered at every position by
`Flicker.CursorContextTest`/`Flicker.CursorContextPropertyTest`; real
cursor-position reporting through the full component (a mid-token cursor
producing the correct `{:value, facet, prefix}` classification and
suggestions, and the end-of-text fallback when no position is reported)
is covered by `Flicker.SearchCursorTest`/`Flicker.SelectCursorTest`. The
dev playground's `/faceted-search` page runs `Flicker.search/1` against
`Dev.Music.Artist` live.
