---
status: ready
date: 2026-07-30
depends_on: [spec-003, spec-012, spec-015, spec-019, adr-011, adr-012, adr-013]
---

# Spec 024: Trigger character for facet entry

Today facet-key suggestions are *always on*: every bare word the user types is
classified `{:key, prefix}` and the dropdown offers matching facet keys
alongside (or instead of) record results. That is right for a dedicated
filter bar, and wrong for a search box whose primary job is free text — the
facet machinery is permanently in the way of typing a name.

This spec adds an opt-in **trigger character**. With `facet_trigger="@"`, plain
words search records and nothing else; typing `@` at the start of a token opens
a facet-key menu; picking a key opens that facet's Spec 019 editor directly. The
trigger is *input sugar only* — it never reaches `Flicker.Query`, a token, a
pill, or a URL.

## Scope

- A new attr on `Flicker.search/1`, `Flicker.select/1` and `Flicker.palette/1`:

  ```heex
  <Flicker.search facet_trigger="@" resource={MyApp.Artist} facets={[:status, :created_at]} />
  ```

  Accepted shapes:

  - `nil` (default) — today's always-on behaviour, unchanged.
  - a one-grapheme string — a single trigger offering the whole facet registry.
  - a map of grapheme to facet keys — per-trigger scoping, so `@` can mean
    people and `#` can mean tags:

    ```heex
    <Flicker.search facet_trigger={%{"@" => [:worker, :owner], "#" => [:tag]}} ... />
    ```

- When a trigger is configured, `{:key, _}` fires **only** for a token that
  starts with a trigger grapheme. Every other token is `:text`.
- Picking a key suggestion inserts the canonical token text (`status:`) and
  **discards the trigger**.
- A new attr `open_editor_on_pick`. Defaults to `true` when `facet_trigger` is
  set and `false` otherwise, so no existing usage changes behaviour. When true,
  picking a key whose facet is `Flicker.FacetEditor.editable?/1` opens that
  editor immediately instead of leaving the user in `{:value, facet, ""}` with an
  inline picklist.
- A themed, localised affordance telling the user the trigger exists: theme part
  `facet_trigger_hint`, message key `:facet_trigger_hint` with the trigger
  bound.
- `Flicker.Trigger` — a new pure module owning parsing/validation of the attr
  and the token test, so both components and the two editors share one
  definition.

## Non-goals

- **No grammar change.** `Flicker.Query.parse/2` never sees a trigger and gains
  no clause. `@status:active` is not valid query text and never will be; the
  parser's input is always `status:active`.
- **Not a mention system.** This does not insert rich-text mentions, resolve
  `@casey` to a user record, or maintain any entity map. It picks a *facet key*.
- **No multi-grapheme sequences** (`//`, `>>`). One grapheme per trigger, so the
  token test stays a single comparison and the caret arithmetic stays trivial.
- **No trigger-only mode for values.** Once a key is committed, value entry is
  exactly Spec 003 / Spec 019 as it is today.
- **No escape syntax.** Degradation (below) makes one unnecessary.

## Design

### The invariant

The trigger is a *mode switch in the input*, not a token character. Everything
downstream of the key suggestion — the token, `Flicker.Query`, the pill, the
editor's `serialise`, the URL — is byte-identical to what it is without a
trigger configured. This is the same separation ADR-013 draws between canonical
tokens and localised display, applied to input affordances: the affordance is
allowed to be configurable precisely because nothing persists it.

Consequence for tests: every existing round-trip and parse test stays valid
unchanged, and the new tests assert *absence* — no trigger grapheme survives
into `query.text`, `query.facets`, or any token an editor produces.

### `Flicker.Trigger`

```elixir
defmodule Flicker.Trigger do
  @type t :: %{String.t() => [atom()] | :all}

  @spec parse(nil | String.t() | map() | keyword()) :: {:ok, t() | nil} | {:error, term()}

  @doc "The trigger the token starts with, and the facets it offers, or `nil`."
  @spec match(t() | nil, [char()] | String.t()) :: {String.t(), [Flicker.Facet.t()]} | nil

  @doc "Graphemes a host has configured, in configuration order — for the hint."
  @spec graphemes(t() | nil) :: [String.t()]
end
```

`parse/1` rejects a multi-grapheme trigger, whitespace, and a grapheme that
`Flicker.CursorContext` would treat as a key character (a letter, digit, `_` or
`?`) — `s` as a trigger would be unresolvable from a key's first letter. It
raises at component-render time rather than degrading, because a mistyped
trigger silently disabling all facets is worse than a crash in dev.

`:` **is** allowed, and is worth calling out: it is the operator, but the
operator only ever appears *after* a key run, so a token-initial `:` is
unambiguous. `:stat` is a trigger; `status:` is not.

### Classification

`Flicker.CursorContext.classify/3` grows an optional fourth argument (or an
options keyword — implementer's choice, but keep `classify/3` working for the
no-trigger case, since its property tests call it directly):

```elixir
CursorContext.classify(input, cursor, facets, trigger \\ nil)
```

With `trigger` non-nil, for the token under the cursor:

1. If the token's first grapheme is a configured trigger, drop it and classify
   the remainder as today, but against **that trigger's** facet subset. A bare
   `@` with the cursor after it is `{:key, ""}` — the full menu.
2. Otherwise, if the token resolves to a known facet with a legal operator, it
   is still `{:value, facet, prefix}`. A trigger gates *discovery*, not
   *recognition*: a user (or a restored URL) who types `status:acti` in full
   still gets value suggestions, and a pasted query still works. This is the
   single most important behavioural nuance in the spec — the trigger must not
   make typed-out or pasted queries stop working.
3. Otherwise `:text`.

The returned state deliberately does **not** carry the trigger. Callers that
need it for insertion arithmetic use `Flicker.Trigger.match/2` on the token
themselves, which keeps `CursorContext.t()` unchanged and every existing
`case` over it exhaustive.

### Insertion, and where the trigger goes

`FacetSuggest.replace_current_token/3` already replaces the whole token found by
`CursorContext.token_bounds/2`. Since the trigger is part of that token, this
needs *no change at all*: `@stat` → `status:` drops the trigger as a consequence
of replacing the token, not as a special case. Assert that explicitly in a test
so a future refactor can't reintroduce `@status:`.

### Degradation, and typing a literal trigger

A trigger only counts at a **token start**, which handles the common cases for
free:

- `casey@example.com` — the `@` is mid-token, so the whole thing is free text.
- `@nonsense` where no facet key starts with `nonsense` — the key menu shows
  empty, and if the user keeps typing and dispatches, the token degrades to free
  text **including the trigger grapheme**, matching how ADR-012 already degrades
  an unknown facet key. Searching for the literal text `@handle` therefore just
  works.
- Escape dismisses the menu for the current token and stays dismissed until the
  caret leaves it, so the menu can be got rid of without deleting anything.

### The hint

With no trigger, an empty faceted input's dropdown lists facet keys, which is
its own discovery mechanism. With a trigger, that list is gone and discoverability
has to be replaced deliberately, or the feature is invisible. Render
`facet_trigger_hint` in the input's empty state and in the free-text state:

> Type **@** to filter

with the graphemes joined by `Localize.List` when localisation is available and
`Flicker.Facet.Format`'s fallback otherwise (ADR-013 — `Format` remains the only
module allowed to call `Localize.*`).

### Announcements

- Reuse `:facet_key_context` when the trigger fires. A screen reader user has
  the same need as before: "Typing a facet name".
- Add `:facet_trigger_hint` — `%{triggers: ["@", "#"]}` — used for both the
  visible hint and as the input's `aria-describedby` text, so the affordance is
  announced on focus rather than only being visible.
- Every string goes through `Flicker.Messages` (ADR-009); the
  `no_hardcoded_text_test` covers the new part automatically.

### Editor auto-open

When `open_editor_on_pick` is true and the picked facet is editable, the pick
handler commits the key token *and* opens the editor in one round trip. The
editor is already a modal sub-context that commits atomically (ADR-011), so this
is the flow the user is actually after: `@` → pick `created_at` → the calendar
is focused, with no intermediate state where a half-typed `created_at:` sits in
the input. Cancelling the editor leaves the key token in place, as it does today
— it does not undo the pick, because the user did choose the facet.

For a non-modal editor (the switch, per ADR-011) "open" means rendering it
inline in the dropdown; there is no pop-out.

### Playground

`/faceted-search` gains a trigger toggle so the two modes can be compared
side by side, and the `%{"@" => …, "#" => …}` scoped form gets its own example
with copyable code (Spec 014).

## Acceptance criteria

1. With no `facet_trigger`, classification, suggestions, insertion and
   announcements are identical to today — asserted by the existing Spec 003
   suite passing unchanged.
2. With `facet_trigger="@"`, typing `stat` classifies `:text` and offers zero
   facet-key suggestions.
3. With `facet_trigger="@"`, typing `@stat` classifies `{:key, "stat"}` and
   offers `status:`.
4. A bare `@` offers every facet in that trigger's subset.
5. Picking `status:` from `@stat` yields input text `status:` — no `@` anywhere
   in it.
6. `Flicker.Query.parse/2` never receives a trigger grapheme: for every trigger
   shape and every editor, the committed input parses with `invalid == []` and
   the resulting `query.text` contains no trigger grapheme.
7. `status:acti` typed in full still classifies `{:value, status_facet, "acti"}`
   with a trigger configured — a pasted or restored query is unaffected.
8. `casey@example.com` classifies `:text` and produces free text containing the
   literal `@`.
9. `@nope` with no matching key dispatches as free text `@nope`.
10. Scoped triggers: with `%{"@" => [:worker], "#" => [:tag]}`, `@` offers only
    `worker:` and `#` only `tag:`; a facet in neither is unreachable by trigger
    but still recognised when typed out (criterion 7).
11. `Flicker.Trigger.parse/1` rejects `""`, `"@@"`, `" "`, and `"s"` (a key
    character), and accepts `"@"`, `"#"`, `"/"`, `":"`.
12. With `facet_trigger` set, `open_editor_on_pick` defaults true: picking
    `created_at:` opens the calendar with focus inside the dialog. Without a
    trigger it defaults false and picking is unchanged.
13. Cancelling an auto-opened editor leaves the key token in the input and the
    caret after the operator.
14. The hint renders the configured graphemes, comes from `Flicker.Messages`,
    and is referenced by the input's `aria-describedby`.
15. The trigger flow announces via `:facet_key_context`, and the axe scan on the
    playground's trigger example is clean.
16. Property: for arbitrary input, cursor and trigger config, `classify/4` never
    raises and returns one of the three existing states.

## Open questions

None blocking. Two worth revisiting after the playground exists:

- Should a trigger grapheme typed mid-token *after whitespace-less punctuation*
  (`foo,@bar`) count as a token start? Treating only whitespace as a boundary is
  the conservative choice and is what this spec says; real use may argue for
  splitting on punctuation too.
- Whether "the trigger is sugar, never grammar" deserves promoting from this
  spec's Design section to its own ADR. It is a genuine architectural boundary,
  and a second input affordance (a `>` command prefix, say) would make it one.
