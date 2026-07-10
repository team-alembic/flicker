# Flicker

[![CI](https://github.com/team-alembic/flicker/actions/workflows/elixir.yml/badge.svg)](https://github.com/team-alembic/flicker/actions/workflows/elixir.yml)
[![Hex version badge](https://img.shields.io/hexpm/v/flicker.svg)](https://hex.pm/packages/flicker)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/flicker)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

Ash-native searchable select, multi-select, and faceted search for Phoenix
LiveView — what [Cinder](https://hex.pm/packages/cinder) is for tables,
Flicker is for finding and picking records. See
[docs/DESIGN.md](https://github.com/team-alembic/flicker/blob/main/docs/DESIGN.md)
for the design overview.

## Installation

Add `flicker` to the list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:flicker, "~> 0.1"}
  ]
end
```

## Features

- **Ash-native** — `Flicker.select/1` reads directly off an Ash resource
  (`resource` + `search` + `option_label`), no options plumbing, no host
  web module. Escape to a custom `Flicker.Provider` for federated search
  or a non-Ash source.
- **Actor-scoped authorization** — every read runs through Ash policies
  against the `actor` you pass; there's no separate permission system.
- **Single- and multi-select** — the same component is the multi-select
  surface (`multiple`); selections render as removable chips, form-field
  mode emits `name[]` array inputs, `fetch/2` resolves every preselected
  value in one call.
- **Faceted search** — Datadog-style `status:active worker:"Casey" after:7d
  free text`, parsed and autocompleted straight from the Ash type system.
  `Flicker.search/1` is the standalone filter bar; the same `facets` attr
  narrows `Flicker.select/1` and `Flicker.palette/1` too.
- **Command palette** — `Flicker.palette/1`, a ⌘K fullscreen overlay
  wrapping the same core, with grouped results and navigate-on-select.
- **Themeable** — a class-per-part `Flicker.Theme` map, no hardcoded CSS
  framework. Vanilla, Tailwind, and daisyUI presets ship; override any
  part globally or per-component.
- **Accessible by design** — WAI-ARIA APG editable-combobox semantics,
  polite live-region announcements for every state change, all
  user-facing text overridable through `Flicker.Messages`.
- **Installs via Igniter** — `mix igniter.install flicker` wires the
  colocated JS hook and default config for you.

## Usage

Pick one, actor-scoped, off an Ash resource:

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

A standalone faceted filter bar driving your own list or table:

```heex
<Flicker.search
  id="artist-search"
  resource={MyApp.Artist}
  actor={@current_user}
  facets={[:status, :genre, after: [attribute: :formed_on, op: :>=]]}
  on_change={:artist_query_changed}
/>
```

```elixir
def handle_info({:artist_query_changed, _query, filter}, socket) do
  artists = MyApp.Artist |> Ash.Query.filter_input(filter) |> Ash.read!(actor: socket.assigns.current_user)
  {:noreply, assign(socket, :artists, artists)}
end
```

A ⌘K command palette:

```heex
<Flicker.palette
  id="cmdk"
  source={MyApp.Search.Global}
  actor={@current_user}
  open={@palette_open}
  on_close={:palette_closed}
  on_select={:palette_selected}
/>
```

See the [getting started guide](https://hexdocs.pm/flicker/getting-started.html)
and the rest of the [online documentation](https://hexdocs.pm/flicker) for
the full guide set — theming, writing your own provider, faceted search,
the command palette, accessibility, and Cinder interop.

## Playground

The repo ships an in-repo dev playground — a seeded Ash domain and a page
per capability, no database required:

```bash
mix deps.get
mix dev
```

Then visit `http://localhost:4000` for an index of pages: single- and
multi-select, the three theme presets, faceted search, the command
palette, keyboard activation, edge states (errors, empty results), and
the Cinder interop recipe.

## Development

Requires Elixir / OTP as pinned in
[`.tool-versions`](https://github.com/team-alembic/flicker/blob/main/.tool-versions).

```bash
mix deps.get
mix check        # full local quality suite
mix test         # just the tests
mix format       # format all files
```

Or use the included [devcontainer](./.devcontainer/devcontainer.json) — opens
with VS Code or any devcontainer-compatible editor and sets up Elixir + asdf
automatically.

## Releases

Releases are automated via [`git_ops`](https://hex.pm/packages/git_ops) and
conventional commits. To cut a release:

```bash
mix git_ops.release
git push && git push --tags
```

Then create a GitHub Release from the tag — the `release.yml` workflow
publishes to Hex on your behalf.

## License

Apache 2.0. See
[LICENSE](https://github.com/team-alembic/flicker/blob/main/LICENSE).

---

<sub>This repository was generated from [team-alembic/elixir_package_template](https://github.com/team-alembic/elixir_package_template).</sub>
