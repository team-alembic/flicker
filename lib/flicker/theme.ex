defmodule Flicker.Theme do
  @moduledoc """
  A class-per-part theme map for the select component (ADR-002).

  Flicker never hardcodes a CSS framework. Instead every visually distinct
  part of the rendered markup has a named key here, and a preset supplies
  the class string for each part. `vanilla/0` (plain, framework-free class
  names a host hooks their own CSS onto) is the only preset shipped in this
  stage — Tailwind and daisyUI presets land in a follow-up stage, built
  against these same keys.

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
          hint: String.t()
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
            hint: "flicker-hint"

  @doc "The default preset: plain, framework-free `flicker-*` class names."
  @spec vanilla() :: t()
  def vanilla, do: %__MODULE__{}

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
