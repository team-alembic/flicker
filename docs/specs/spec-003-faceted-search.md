---
status: draft
date: 2026-07-10
depends_on: [spec-001, spec-002, adr-001]
---

# Spec 003: Faceted / scoped filtering

Datadog-style `status:active worker:"Casey Nguyen" after:7d free text`, where
each facet maps to an Ash filter and facet-value autocomplete is derived from
the Ash type system. The differentiating feature — highest risk, built last
on a proven base. A mini-project: expect this spec to split into sub-specs
once the prototype lands.

## Scope

Three pieces:

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

## Open questions

- Facet grammar scope: how far toward Datadog (grouping, `OR`, negation)
  before it's its own query language? Start minimal; extend by demand.
- Does the global-search-bar variant (results grouped by resource type) live
  in Flicker or as a `Flicker.Provider` recipe in docs?
- Relative-date grammar (`7d`, `2w`) — fixed set or pluggable?
