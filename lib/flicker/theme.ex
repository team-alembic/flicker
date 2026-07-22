defmodule Flicker.Theme do
  @moduledoc """
  A class-per-part theme map for the select component (ADR-002).

  Flicker never hardcodes a CSS framework. Instead every visually distinct
  part of the rendered markup has a named key here, and a preset supplies
  the class string for each part.

  Three presets ship:

    * `vanilla/0` — plain, framework-free `flicker-*` class names a host
      hooks their own CSS onto. The default.
    * `tailwind/0` — Tailwind utility classes, no component library.
    * `daisy_ui/0` — daisyUI component classes (`input`, `menu`,
      `dropdown-content`, ...).

  Every preset covers every key below — see `Flicker.ThemeTest` for the
  assertion that keeps that true as keys are added.

  ## Parts

    * `:wrapper` — the outermost element.
    * `:search_input` — the text input.
    * `:clear_button` — the button that clears the current selection.
    * `:listbox` — the results dropdown.
    * `:option` — a single result row.
    * `:option_active` — added to the active (keyboard-highlighted) option;
      the JS hook toggles this class client-side.
    * `:option_label` — the option's primary label span (default rendering
      only; an `:option` slot owns its own markup).
    * `:option_sublabel` — the option's secondary/sublabel span (default
      rendering only).
    * `:suggestion` — a facet key/value suggestion row (Spec 003); rendered
      in place of `:option` when the listbox is suggesting facets rather
      than records, so suggestions can look distinct from results.
    * `:suggestion_token` — the `status:`/`active` token span inside a
      suggestion row (kbd/mono treatment).
    * `:loading_state` — the listbox's loading row.
    * `:empty_state` — the listbox's no-results row.
    * `:error_state` — the listbox's error row.
    * `:hint` — the "keep typing to narrow results" / min-chars hint row;
      also the tail row shown once a `paginate`-d list hits `max_windows`
      or a provider ignoring `:offset` is detected (Spec 010) — windowing
      degrades into this same hint rather than a separate one.
    * `:loading_more` — `paginate`-d select only (Spec 010): the themed row
      rendered at the listbox tail while the next window loads.
    * `:chip_list` — multi-select: the wrapper around the selected chips.
    * `:chip` — multi-select: a single selected-value chip.
    * `:chip_remove` — multi-select: the per-chip remove button.
    * `:kbd_hint` — the `<kbd>` discoverability hint rendered when
      `activate_with_keyboard` is set (Spec 006); also used for the
      footer's ↑↓/↵/esc hints in `Flicker.palette/1` (Spec 008).
    * `:backdrop` — `Flicker.palette/1`: the full-viewport overlay backdrop
      behind the panel (Spec 008).
    * `:panel` — `Flicker.palette/1`: the centred dialog panel.
    * `:palette_input` — `Flicker.palette/1`: the large search input (in
      place of `:search_input`, which the plain select still uses).
    * `:group_header` — a non-interactive row rendered before the first
      result of each new `result.group` (Spec 008); unused when no result
      in the list carries a `:group`.
    * `:footer` — `Flicker.palette/1`: the panel's footer row of keyboard
      hints.

  ## Resolution

  `resolve/1` merges, in increasing precedence: `vanilla/0`, then
  `config :flicker, default_theme:`, then a per-component override:

      config :flicker, default_theme: %{search_input: "my-input"}

      <Flicker.select theme={%{listbox: "my-listbox"}} ... />

  An override may be a `%Flicker.Theme{}` struct (replaces the base
  wholesale) or a map/keyword list of just the parts to change (merged onto
  the base with `struct!/2`).
  """

  @typedoc "A class-per-part theme map."
  @type t :: %__MODULE__{
          wrapper: String.t(),
          search_input: String.t(),
          clear_button: String.t(),
          listbox: String.t(),
          option: String.t(),
          option_active: String.t(),
          option_label: String.t(),
          option_sublabel: String.t(),
          suggestion: String.t(),
          suggestion_token: String.t(),
          loading_state: String.t(),
          empty_state: String.t(),
          error_state: String.t(),
          hint: String.t(),
          loading_more: String.t(),
          chip_list: String.t(),
          chip: String.t(),
          chip_remove: String.t(),
          kbd_hint: String.t(),
          backdrop: String.t(),
          panel: String.t(),
          palette_input: String.t(),
          group_header: String.t(),
          footer: String.t()
        }

  @typedoc "An override: a full theme, or a partial map/keyword list of parts."
  @type override :: t() | map() | keyword() | nil

  defstruct wrapper: "flicker",
            search_input: "flicker-search-input",
            clear_button: "flicker-clear-button",
            listbox: "flicker-listbox",
            option: "flicker-option",
            option_active: "flicker-option--active",
            option_label: "flicker-option-label",
            option_sublabel: "flicker-option-sublabel",
            suggestion: "flicker-suggestion",
            suggestion_token: "flicker-suggestion-token",
            loading_state: "flicker-loading",
            empty_state: "flicker-empty",
            error_state: "flicker-error",
            hint: "flicker-hint",
            loading_more: "flicker-loading-more",
            chip_list: "flicker-chip-list",
            chip: "flicker-chip",
            chip_remove: "flicker-chip-remove",
            kbd_hint: "flicker-kbd-hint",
            backdrop: "flicker-backdrop",
            panel: "flicker-panel",
            palette_input: "flicker-palette-input",
            group_header: "flicker-group-header",
            footer: "flicker-footer"

  @doc "The default preset: plain, framework-free `flicker-*` class names."
  @spec vanilla() :: t()
  def vanilla, do: %__MODULE__{}

  @doc """
  The Tailwind preset: utility classes only, no component library.

      <Flicker.select theme={Flicker.Theme.tailwind()} ... />

  or globally via `config :flicker, default_theme: Flicker.Theme.tailwind()`.
  """
  @spec tailwind() :: t()
  def tailwind do
    %__MODULE__{
      wrapper: "relative w-full",
      search_input:
        "w-full rounded-md border border-gray-300 px-3 py-2 text-sm shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 disabled:cursor-not-allowed disabled:opacity-50",
      clear_button: "absolute inset-y-0 right-2 flex items-center text-gray-400 hover:text-gray-600",
      listbox:
        "absolute z-10 mt-1 max-h-60 w-full overflow-auto rounded-md bg-white py-1 text-sm shadow-lg ring-1 ring-black/5 focus:outline-none",
      option: "cursor-pointer select-none px-3 py-2 text-gray-900 hover:bg-indigo-50",
      option_active: "bg-indigo-100 text-indigo-900",
      option_label: "font-medium",
      option_sublabel: "ml-2 text-xs text-gray-400",
      suggestion: "cursor-pointer select-none px-3 py-2 hover:bg-indigo-50",
      suggestion_token:
        "mr-2 inline-block rounded border border-gray-200 bg-gray-50 px-1.5 py-0.5 font-mono text-xs text-indigo-700",
      loading_state: "px-3 py-2 text-gray-500",
      empty_state: "px-3 py-2 text-gray-500",
      error_state: "px-3 py-2 text-red-600",
      hint: "px-3 py-2 text-xs text-gray-400",
      loading_more: "px-3 py-2 text-xs text-gray-400",
      chip_list: "flex flex-wrap gap-1",
      chip: "inline-flex items-center gap-1 rounded-full bg-indigo-50 px-2 py-1 text-xs text-indigo-700",
      chip_remove: "text-indigo-400 hover:text-indigo-700",
      kbd_hint:
        "pointer-events-none absolute inset-y-0 right-2 flex items-center rounded border border-gray-300 px-1.5 text-xs text-gray-400",
      backdrop: "fixed inset-0 z-40 bg-gray-900/50",
      panel:
        "fixed left-1/2 top-24 z-50 w-full max-w-xl -translate-x-1/2 overflow-hidden rounded-lg bg-white shadow-2xl",
      palette_input: "w-full border-0 border-b border-gray-200 px-4 py-3 text-base focus:outline-none",
      group_header: "px-3 py-1.5 text-xs font-semibold uppercase tracking-wide text-gray-400",
      footer: "flex items-center gap-4 border-t border-gray-100 px-4 py-2 text-xs text-gray-400"
    }
  end

  @doc """
  The daisyUI preset: `input`, `menu`, `dropdown-content`, and friends.

      <Flicker.select theme={Flicker.Theme.daisy_ui()} ... />

  or globally via `config :flicker, default_theme: Flicker.Theme.daisy_ui()`.
  """
  @spec daisy_ui() :: t()
  def daisy_ui do
    %__MODULE__{
      wrapper: "dropdown w-full",
      search_input: "input input-bordered w-full",
      clear_button: "btn btn-ghost btn-xs absolute right-2 top-1/2 -translate-y-1/2",
      listbox:
        "menu dropdown-content menu-sm z-10 mt-1 max-h-60 w-full flex-nowrap overflow-auto rounded-box bg-base-100 p-2 shadow",
      # No `hover:bg-*` here: daisyUI's `menu` component (applied to the
      # listbox `<ul>`) already paints its own hover background on each
      # `<li>`'s interactive child (the option `<button>`) — adding a
      # second Tailwind `hover:bg-base-200` utility on the `<li>` itself
      # stacked a second, differently-positioned hover highlight on top of
      # daisyUI's own (BUG 4: double hover on option rows).
      option: "cursor-pointer rounded-md px-3 py-2",
      option_active: "bg-primary text-primary-content",
      option_label: "font-medium",
      option_sublabel: "ml-2 text-xs opacity-60",
      suggestion: "cursor-pointer rounded-md px-3 py-2",
      suggestion_token: "kbd kbd-sm mr-2",
      loading_state: "px-3 py-2 text-base-content/60",
      empty_state: "px-3 py-2 text-base-content/60",
      error_state: "px-3 py-2 text-error",
      hint: "px-3 py-2 text-xs text-base-content/50",
      loading_more: "px-3 py-2 text-xs text-base-content/50",
      chip_list: "flex flex-wrap gap-1",
      chip: "badge badge-primary gap-1",
      chip_remove: "cursor-pointer",
      kbd_hint: "kbd kbd-sm pointer-events-none absolute right-2 top-1/2 -translate-y-1/2",
      backdrop: "fixed inset-0 z-40 bg-black/40",
      panel: "modal-box fixed left-1/2 top-24 z-50 w-full max-w-xl -translate-x-1/2 p-0",
      palette_input: "input input-ghost w-full border-0 border-b border-base-200 text-base focus:outline-none",
      group_header: "px-3 py-1.5 text-xs font-semibold uppercase tracking-wide text-base-content/50",
      footer: "flex items-center gap-4 border-t border-base-200 px-4 py-2 text-xs text-base-content/50"
    }
  end

  @doc """
  Resolves the effective theme for a component instance, merging (lowest to
  highest precedence) `vanilla/0`, `config :flicker, :default_theme`, and
  `component_override`.
  """
  @spec resolve(override()) :: t()
  def resolve(component_override \\ nil) do
    vanilla()
    |> merge(Application.get_env(:flicker, :default_theme))
    |> merge(component_override)
  end

  defp merge(_theme, %__MODULE__{} = override), do: override
  defp merge(theme, nil), do: theme

  defp merge(theme, override) when is_map(override) or is_list(override), do: struct!(theme, override)
end
