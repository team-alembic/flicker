---
status: current
date: 2026-07-10
---

# Extraction notes — the origin implementation

Flicker is extracted from a searchable-select component proven in a
production Ash/LiveView application (referred to here only as "the origin
app"). These notes make this repo self-contained: they carry the
implementation knowledge — especially the hard-won, easy-to-get-wrong parts
— so specs 001/004 can be implemented without access to the origin
codebase. Module and UI-helper names below are neutralised.

**Delete this file once Spec 001 ships** — at that point the library's own
code and tests are the reference.

## Shape of the origin implementation

A `Phoenix.LiveComponent` (`SearchableSelect`) + a per-record-type
behaviour (`Search.Source`) + a display struct (`Search.Result`) + a JS
keyboard hook + a PhoenixTest helper. Flicker's renames: `Search.Source` →
`Flicker.Provider`, `Search.Result` → `Flicker.Result`.

### The behaviour (origin `Search.Source`)

```elixir
@callback search(query :: String.t(), actor :: term(), limit :: pos_integer(), opts :: keyword()) ::
            {:ok, [Result.t()]} | {:error, term()}
@callback fetch(value :: String.t(), actor :: term()) :: {:ok, Result.t()} | {:error, term()}
@callback read_permission() :: String.t()   # dropped in Flicker — ADR-004
```

Deltas already decided: `fetch` takes a list (ADR-003); `read_permission`
replaced by actor/policy scoping (ADR-004); query becomes a struct
(`%Flicker.Query{}`); opts absorb actor/tenant/limit (Spec 004).

Reusable detail — sublabel joining, drop-blanks-then-middot:

```elixir
def sublabel(parts) do
  case Enum.filter(parts, & &1) do
    [] -> nil
    parts -> Enum.join(parts, " · ")
  end
end
```

A source implementation is ~60 lines: blank query → sorted first-`limit`
listing (the picker's open state); non-blank → the resource's search
action; both `actor:`-scoped, mapped to `Result` structs. The origin
`Result` carried `type/type_label/icon/path/bg_class` — in Flicker those
collapse into `meta` + slots (ADR-002); `bg_class/1` living on the struct
is exactly the coupling the theme system replaces.

## The hard-won parts (port these faithfully)

### 1. `_unused_` marker — required-error suppression + reconnect recovery

Phoenix's `used_input?/1` treats a field as pristine while a
`_unused_<field>` param accompanies it. Native inputs get this from
LiveView's form recovery; a custom picker must emit the marker itself or
the required error fires before the user touches anything.

Render side — the marker input only exists while the field is empty:

```heex
<input type="hidden" name={@field.name} id={@field.id} value={@field.value} required={@required} />
<%!-- Marks the field untouched (like LiveView does for native inputs) so a
required error doesn't surface until the user engages this picker. Dropped
by the selection hook, and only rendered while nothing is chosen. --%>
<input :if={blank?(@field.value)} type="hidden" name={unused_marker_name(@field)} value="" />
```

```elixir
# e.g. "form[_unused_worker_id]" — the field's own form scope matters
defp unused_marker_name(field), do: "#{field.form.name}[_unused_#{field.field}]"
```

Errors are only shown when engaged:
`if used_input?(@field), do: translate(@field.errors), else: []`.

### 2. Applying a selection without wiping sibling fields

Selection is applied in the parent via an attached `handle_info` hook (the
component `send`s `{__MODULE__, :selected, field_name, value}`). The
critical part is **merging into the form's existing raw params** — validating
with the selection alone would reset every other field's in-progress state
and their `_unused_` markers:

```elixir
# field_name arrives in bracket notation, e.g. "form[client_id]";
# handle only messages rooted in the configured form, else {:cont, socket}
params =
  (form.source.params || %{})
  |> Map.put(key, value)
  |> Map.delete("_unused_#{key}")   # the field is now used

new_form = AshPhoenix.Form.validate(form, params)
```

The public shape: `SearchableSelect.attach(socket, form: :form)` in
`mount/3` installs one `attach_hook/4` handling every picker in that form;
optional `on_select: fn socket, params -> socket end` runs after
revalidation. In Flicker this whole mechanism is the *optional
AshPhoenix.Form adapter* (ADR-005) — controlled mode bypasses it.

### 3. `has_more` without a count query

Fetch `limit + 1`, display `limit`, `has_more = length > limit` → renders
"Keep typing to narrow results…" instead of paginating. A typeahead's
narrowing *is* the interaction; there is nothing to scroll.

```elixir
case source.search(String.trim(query), actor, max + 1, query_opts) do
  {:ok, results} ->
    assign(socket, results: Enum.take(results, max), has_more: length(results) > max)
  {:error, error} ->
    Logger.warning("search failed: #{inspect(error)}")
    assign(socket, results: [], has_more: false)
end
```

### 4. Resolving the selected value's label (edit forms)

The selected record is usually not in the loaded results (edit form opens
with a value set). Resolve via `fetch`, but skip when unchanged — and
compare **string-to-string**, since form values are strings and struct
values may not be:

```elixir
cond do
  blank?(value) -> assign(socket, selected: nil)
  selected && to_string(selected.value) == to_string(value) -> socket
  true -> assign(socket, selected: fetch_selected(socket, value))
end
```

`fetch` failure logs a warning and renders as no selection — never crashes
the form.

### 5. Component event flow

`open` → reset query, load blank-query results, `push_event` focusing the
search input (the trigger button that had focus is removed from the DOM
when the dropdown opens — focus must be moved explicitly). `query` →
`phx-debounce="150"` on the input. `select`/`clear` → send to parent,
close. `phx-click-away` and `Escape` (`phx-keydown` + `phx-key`) close.
Selected option is found in the loaded results by string-compared value.

### 6. The JS keyboard hook (origin `SearchableSelectNav`, verbatim minus one class)

```js
const SearchableSelectNav = {
  mounted() {
    this.activeIndex = -1
    // Listen on the wrapper, not the input: the input node is re-rendered as
    // the results change, which would strip a listener bound to it, and keydown
    // bubbles up from the focused input to here anyway.
    this.onKeydown = e => this.handleKeydown(e)
    this.el.addEventListener("keydown", this.onKeydown)
    // Focus the search box so keys land here even though the trigger button
    // that had focus was removed when the dropdown opened.
    this.input()?.focus()
  },
  updated() {
    // The option set changed (the user typed) — start fresh with no highlight.
    this.activeIndex = -1
    this.render()
  },
  destroyed() {
    this.el.removeEventListener("keydown", this.onKeydown)
  },
  input() { return this.el.querySelector('input[type="text"]') },
  options() { return Array.from(this.el.querySelectorAll('[role="option"]')) },
  handleKeydown(e) {
    const options = this.options()
    if (options.length === 0) return
    const move = delta => {
      e.preventDefault()
      this.activeIndex = (this.activeIndex + delta + options.length) % options.length
      this.render()
    }
    switch (e.key) {
      case "ArrowDown": move(1); break
      case "ArrowUp": move(-1); break
      case "Tab":
        // Tab/Shift+Tab drive the same highlight as the arrows rather than
        // moving focus out of the open dropdown.
        move(e.shiftKey ? -1 : 1)
        break
      case "Enter":
        // Prevent submitting the surrounding form; pick the highlight if any.
        e.preventDefault()
        if (this.activeIndex >= 0) options[this.activeIndex].querySelector("button").click()
        break
    }
  },
  render() {
    const input = this.input()
    this.options().forEach((option, i) => {
      const active = i === this.activeIndex
      option.setAttribute("aria-selected", active ? "true" : "false")
      option.querySelector("button").classList.toggle("<active-class>", active)  // theme part in Flicker
      if (active) {
        input?.setAttribute("aria-activedescendant", option.id)
        option.scrollIntoView({block: "nearest"})
      }
    })
    if (this.activeIndex < 0) input?.removeAttribute("aria-activedescendant")
  },
}
```

Spec 001 deltas: arrows stop at ends (origin wraps via modulo); Tab closes
per the APG map (origin cycles the highlight); the active class comes from
`Flicker.Theme`; ships colocated (ADR-007). The wrapper-listener,
focus-on-mount, highlight-reset-on-update, `preventDefault`-on-Enter, and
`scrollIntoView` behaviours port as-is.

Origin app-JS also carried a generic focus event listener the component's
`push_event` targets — in Flicker this belongs in the colocated hook:

```js
window.addEventListener("phx:focusElementById", e =>
  document.getElementById(e.detail.id).focus())
```

### 7. PhoenixTest helper

```elixir
def search_select(session, trigger_text, option: option) do
  session
  |> PhoenixTest.click_button(trigger_text)
  |> PhoenixTest.click_button(option)
end
```

Drives the picker as a user would (open by prompt-or-selected text, click
option). Flicker's version needs a typing step (`fill_in` the search input)
and multi/facet variants (Spec 001/002 scope).

## Known origin gaps (why the specs demand more)

Confirms what the specs already require rather than inherit: no
`aria-expanded` toggling on the input wrapper, listbox not
`aria-labelledby`, no live-region result-count announcements (Spec 007);
open/close round-trips to the server; no `min_chars`; no stale-result
cancellation beyond debounce (Spec 001); hardcoded CSS-framework classes
and icon set (ADR-002); English strings inline (ADR-009); single-select
only; no `connected?/1` gating — the dead-render lesson in ADR-005 was
learned here.
