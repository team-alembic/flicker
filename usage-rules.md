# Rules for working with Flicker

<!--
  This file is published to Hex alongside the package and is consumed by
  downstream AI agents via `mix usage_rules.sync`. Keep it focused on how to
  USE this package. Developer-facing rules belong in AGENTS.md.
-->

## Understanding Flicker

Flicker is an Ash-native searchable select / combobox for Phoenix
LiveView: a type-to-search, pick-one control that reads directly off an
Ash resource (or any `Flicker.Provider`) — no options plumbing, no host
web module. `Flicker.select/1` is the only public entry point; its
backing `Phoenix.LiveComponent` is a private implementation detail.

## Core concepts

- **`Flicker.select/1`** — the function component. Tier 1: pass
  `resource` + `search` (field list) + `option_label` for the common
  case — Flicker compiles this to the built-in `Flicker.Providers.AshResource`
  provider. Tier 2: pass `source` (a module, or `{module, opts}`)
  implementing `Flicker.Provider` yourself for custom or federated search.
- **Modes** — exactly one of `field` (form-field mode: the component owns
  its hidden input and `_unused_` recovery marker) or `on_select` (an
  atom; controlled mode: your `handle_info/2` gets
  `{on_select, %Flicker.Result{} | nil}`) is required.
- **`actor`** — always pass it. It's the only authorization boundary:
  Flicker has no separate permission system, it relies entirely on Ash
  policies evaluated against the `actor` you give it. Omitting it means
  every read runs as `nil` actor.
- **`Flicker.Theme`** — a class-per-part styling map. Presets:
  `vanilla/0` (default), `tailwind/0`, `daisy_ui/0`. Override globally via
  `config :flicker, default_theme:` or per-component via the `theme` attr.
- **`Flicker.Messages`** — every visible string and every screen-reader
  announcement routes through this behaviour. Override globally via
  `config :flicker, messages:` or per-component via the `messages` attr.
- **`multiple`** — switches the value model to a list: selections render
  as removable chips, form-field mode emits `name[]` array inputs, and
  controlled mode's `on_select` carries the full selection list on every
  change. `max_selections` caps how many can be picked. Same component,
  no separate multi-select module.

## Basic usage

```heex
<Flicker.select
  id="client-select"
  field={@form[:client_id]}
  resource={MyApp.Client}
  actor={@current_user}
  search={[:first_name, :last_name, :uci_number]}
  option_label={:full_name}
/>
```

## Common patterns

### Controlled mode (no form)

```heex
<Flicker.select
  id="global-search"
  source={MyApp.Search.Global}
  actor={@current_user}
  on_select={:result_selected}
/>
```

```elixir
def handle_info({:result_selected, result}, socket) do
  {:noreply, assign(socket, :selected, result)}
end
```

### Multi-select with chips

```heex
<Flicker.select
  id="worker-select"
  field={@form[:worker_ids]}
  multiple
  resource={MyApp.Worker}
  actor={@current_user}
  search={[:name]}
  option_label={:name}
  max_selections={5}
/>
```

An edit form opening with `worker_ids` already set resolves every
preselected value in one `fetch/2` call, regardless of how many there are.

### Overriding a message

Only implement the keys you want to change; delegate the rest to
`Flicker.Messages.English`:

```elixir
defmodule MyAppWeb.FlickerMessages do
  @behaviour Flicker.Messages

  @impl true
  def message(:search_placeholder, _bindings), do: "Rechercher..."
  def message(key, bindings), do: Flicker.Messages.English.message(key, bindings)
end
```

```elixir
config :flicker, messages: MyAppWeb.FlickerMessages
```

### Overriding a theme part

```heex
<Flicker.select theme={%{search_input: "my-custom-input"}} ... />
```

A partial map/keyword override merges onto the base theme with
`struct!/2`; pass a full `%Flicker.Theme{}` (e.g. `Flicker.Theme.tailwind()`)
to replace it wholesale.

### Testing a select

```elixir
test "picks a client", %{conn: conn} do
  conn
  |> visit(~p"/clients/new")
  |> Flicker.Test.search_select("Search...", "Casey Cassidy")
  |> assert_has("#client-select-input[value='Casey Cassidy']")
end
```

Requires `phoenix_test` in your own `:test` deps.

## Anti-patterns

- Do **not** omit `actor` — there's no other read-authorization boundary;
  every result and every `fetch` resolves with whatever that actor can
  see.
- Do **not** write a partial `Flicker.Messages` override that raises
  inside a clause it does handle — `Flicker.Messages.get/3` only falls
  back to `Flicker.Messages.English` when the override doesn't implement
  a key at all (a `FunctionClauseError`), not when an implemented clause
  itself errors.
- Avoid reaching for a custom `Flicker.Provider` when Tier 1 config
  (`resource` + `search` + `option_label`) already covers the case — it's
  strictly less code and stays authorized the same way.

## See also

- [HexDocs](https://hexdocs.pm/flicker)
- [Getting started guide](https://hexdocs.pm/flicker/getting-started.html)
