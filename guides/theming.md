# Theming

Flicker never hardcodes a CSS framework (ADR-002). Every visually
distinct part of the rendered markup — the wrapper, the input, the
listbox, an option, its active state, and more — has a named key in
`Flicker.Theme`, and a preset supplies the class string for each part.

## Presets

Three ship, all covering every part:

- `Flicker.Theme.vanilla/0` — plain, framework-free `flicker-*` class
  names for a host to hook its own CSS onto. The default.
- `Flicker.Theme.tailwind/0` — Tailwind utility classes, no component
  library.
- `Flicker.Theme.daisy_ui/0` — daisyUI component classes (`input`,
  `menu`, `dropdown-content`, and friends).

Set one globally:

```elixir
config :flicker, default_theme: Flicker.Theme.tailwind()
```

or per-component:

```heex
<Flicker.select theme={Flicker.Theme.daisy_ui()} ... />
```

## Overriding individual parts

An override doesn't have to be a full preset — a map or keyword list of
just the parts you want to change merges onto the base theme:

```heex
<Flicker.select theme={%{search_input: "my-custom-input", listbox: "my-listbox"}} ... />
```

Resolution order (lowest to highest precedence):
`Flicker.Theme.vanilla/0` → `config :flicker, default_theme:` → the
component's own `theme` attr. A full `%Flicker.Theme{}` struct replaces
the base wholesale; a plain map/keyword list merges onto it with
`struct!/2`, leaving every unmentioned part at whatever the previous tier
set.

## Parts reference

| Part | Where it applies |
|---|---|
| `:wrapper` | The outermost element. |
| `:search_input` | The text input. |
| `:clear_button` | The button that clears the current selection. |
| `:listbox` | The results dropdown. |
| `:option` | A single result row. |
| `:option_active` | Added to the active (keyboard-highlighted) option; toggled client-side by the JS hook. |
| `:loading_state` | The listbox's loading row. |
| `:empty_state` | The listbox's no-results row. |
| `:error_state` | The listbox's error row. |
| `:hint` | The "keep typing to narrow results" / min-chars hint row. |
| `:chip_list` | Multi-select: the wrapper around the selected chips. |
| `:chip` | Multi-select: a single selected-value chip. |
| `:chip_remove` | Multi-select: the per-chip remove button. |
| `:kbd_hint` | The `<kbd>` discoverability hint when `activate_with_keyboard` is set; also the palette footer's ↑↓/↵/esc hints. |
| `:backdrop` | `Flicker.palette/1`: the full-viewport overlay backdrop behind the panel. |
| `:panel` | `Flicker.palette/1`: the centred dialog panel. |
| `:palette_input` | `Flicker.palette/1`: the large search input (in place of `:search_input`). |
| `:group_header` | A non-interactive row before the first result of each new `result.group` (unused unless a result carries `:group`). |
| `:footer` | `Flicker.palette/1`: the panel's footer row of keyboard hints. |

See `Flicker.Theme`'s moduledoc for the authoritative list — it's kept in
sync with the struct definition by `Flicker.ThemeTest`.

## Building your own preset

A theme is just a `%Flicker.Theme{}` struct — build one directly for a
design system none of the three presets match:

```elixir
defmodule MyApp.FlickerTheme do
  @moduledoc "Flicker theme matching MyApp's design system."

  @spec preset() :: Flicker.Theme.t()
  def preset do
    %Flicker.Theme{
      wrapper: "my-app-search",
      search_input: "my-app-input",
      listbox: "my-app-listbox",
      option: "my-app-option",
      option_active: "my-app-option--active"
      # ... every other part; start from Flicker.Theme.vanilla/0's
      # defaults and override only what your design system needs.
    }
  end
end
```

```elixir
config :flicker, default_theme: MyApp.FlickerTheme.preset()
```

A struct literal like the one above only needs to set the parts your
design system actually changes — `defstruct`'s own `flicker-*` defaults
fill in the rest, same as `Flicker.Theme.vanilla/0`. Set every part
explicitly only if you want a preset with no `vanilla/0` class names left
in it at all.

## Rendering, not markup, per option

Theming covers class names, not structure. For option markup itself —
custom layout beyond a label/sublabel pair — use the `option` slot rather
than a theme part:

```heex
<Flicker.select id="artist-select" resource={Dev.Music.Artist} actor={@current_user} search={[:name]} option_label={:name}>
  <:option :let={result}>
    <div class="flex items-center gap-2">
      <img src={result.meta.avatar_url} class="h-6 w-6 rounded-full" />
      <span>{result.label}</span>
    </div>
  </:option>
</Flicker.select>
```

## Messages vs. theme

Theming controls *how* Flicker looks; `Flicker.Messages` controls *what*
it says — every visible string and screen-reader announcement (ADR-009).
The two compose independently: swap a theme without touching messages,
translate messages without touching a theme. See `Flicker.Messages`'s
moduledoc and the [accessibility guide](accessibility.md) for overriding
strings.

## See also

- `Flicker.Theme` — the full moduledoc, part list, and preset source.
- [Getting started](getting-started.md#theming) — the minimal theming
  example.
