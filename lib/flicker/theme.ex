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
    * `:loading_state` — the listbox's loading row.
    * `:empty_state` — the listbox's no-results row.
    * `:error_state` — the listbox's error row.
    * `:hint` — the "keep typing to narrow results" / min-chars hint row.
    * `:chip_list` — multi-select: the wrapper around the selected chips.
    * `:chip` — multi-select: a single selected-value chip.
    * `:chip_remove` — multi-select: the per-chip remove button.

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
          loading_state: String.t(),
          empty_state: String.t(),
          error_state: String.t(),
          hint: String.t(),
          chip_list: String.t(),
          chip: String.t(),
          chip_remove: String.t()
        }

  @typedoc "An override: a full theme, or a partial map/keyword list of parts."
  @type override :: t() | map() | keyword() | nil

  defstruct wrapper: "flicker",
            search_input: "flicker-search-input",
            clear_button: "flicker-clear-button",
            listbox: "flicker-listbox",
            option: "flicker-option",
            option_active: "flicker-option--active",
            loading_state: "flicker-loading",
            empty_state: "flicker-empty",
            error_state: "flicker-error",
            hint: "flicker-hint",
            chip_list: "flicker-chip-list",
            chip: "flicker-chip",
            chip_remove: "flicker-chip-remove"

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
      loading_state: "px-3 py-2 text-gray-500",
      empty_state: "px-3 py-2 text-gray-500",
      error_state: "px-3 py-2 text-red-600",
      hint: "px-3 py-2 text-xs text-gray-400",
      chip_list: "flex flex-wrap gap-1",
      chip: "inline-flex items-center gap-1 rounded-full bg-indigo-50 px-2 py-1 text-xs text-indigo-700",
      chip_remove: "text-indigo-400 hover:text-indigo-700"
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
      option: "cursor-pointer rounded-md px-3 py-2 hover:bg-base-200",
      option_active: "bg-primary text-primary-content",
      loading_state: "px-3 py-2 text-base-content/60",
      empty_state: "px-3 py-2 text-base-content/60",
      error_state: "px-3 py-2 text-error",
      hint: "px-3 py-2 text-xs text-base-content/50",
      chip_list: "flex flex-wrap gap-1",
      chip: "badge badge-primary gap-1",
      chip_remove: "cursor-pointer"
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
