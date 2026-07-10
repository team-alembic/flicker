defmodule Flicker.Messages.English do
  @moduledoc """
  The complete default `Flicker.Messages` implementation, and the canonical
  list of every message key the select component uses.

  Every key documented here is user-facing — either visible text or a
  screen-reader announcement. Override modules only need to implement the
  keys they want to change (see `Flicker.Messages` for how).
  """

  @behaviour Flicker.Messages

  @impl true
  @doc """
  Resolves `key` (with `bindings`) to English text.

  ## Keys

    * `:search_placeholder` — placeholder text for the search input.
    * `:loading` — shown in the listbox while a search is in flight.
    * `:no_results` — shown when a search returns no results.
    * `:error` — shown when the provider returns an error.
    * `:keep_typing` — shown when more results exist than are displayed
      (`limit`+1 came back) — "keep typing to narrow" rather than paginate.
    * `:min_chars_hint` — %{min_chars: n} — shown while the typed text is
      shorter than the configured `min_chars`.
    * `:results_count` — %{count: n} — the live-region announcement after
      results update.
    * `:clear_selection` — visible text and `aria-label` for the button that
      clears the current selection.
    * `:selected_items` — `aria-label` for the multi-select chip list.
    * `:remove_chip` — %{label: name} — `aria-label` for a chip's remove
      button, naming the chip it removes.
    * `:remove_icon` — the visible glyph on a chip's remove button.
    * `:clear_all` — visible text and `aria-label` for the multi-select
      "clear all" button.
    * `:selected_count` — %{count: n} — the live-region announcement after
      the multi-select selection changes.
    * `:max_selections_reached` — %{max: n} — shown in the listbox once
      `max_selections` is reached.
    * `:keyboard_shortcut_hint` — %{chord: text} — `title` on the
      `activate_with_keyboard` kbd hint (Spec 006), naming the chord that
      focuses and opens the search from anywhere on the page.
    * `:facet_key_context` — the live-region announcement (Spec 003) when
      the cursor moves into facet-key position (`stat|` before any `:`) —
      key suggestions are now driving the dropdown.
    * `:facet_value_context` — %{facet: label} — the live-region
      announcement when the cursor moves into a known facet's value
      position (`status:|`) — that facet's picklist/nested search is now
      driving the dropdown.
    * `:free_text_context` — the live-region announcement when the cursor
      is in plain free-text position — no facet is driving the dropdown.
    * `:facet_key_suggestions_count` — %{count: n} — the live-region
      announcement after facet-key suggestions update.
    * `:facet_value_suggestions_count` — %{count: n} — the live-region
      announcement after facet-value suggestions (enum picklist or nested
      search) update.
    * `:facet_search_placeholder` — placeholder text for `Flicker.search/1`'s
      input.
    * `:palette_label` — `aria-label` for `Flicker.palette/1`'s dialog
      (`role="dialog"`).
    * `:close_palette` — visible text and `aria-label` for the palette's
      close button.
    * `:footer_navigate_hint` — the palette footer's "navigate" kbd hint
      label (next to the ↑↓ keys).
    * `:footer_select_hint` — the palette footer's "select" kbd hint label
      (next to the ↵ key).
    * `:footer_close_hint` — the palette footer's "close" kbd hint label
      (next to the esc key).
  """
  @spec message(atom(), map()) :: String.t()
  def message(:search_placeholder, _bindings), do: "Search..."
  def message(:loading, _bindings), do: "Loading..."
  def message(:no_results, _bindings), do: "No results found"
  def message(:error, _bindings), do: "Something went wrong. Please try again."
  def message(:keep_typing, _bindings), do: "Keep typing to narrow results..."

  def message(:min_chars_hint, %{min_chars: min_chars}), do: "Type at least #{min_chars} characters to search"

  def message(:results_count, %{count: 0}), do: "No results available"
  def message(:results_count, %{count: 1}), do: "1 result available"
  def message(:results_count, %{count: count}), do: "#{count} results available"
  def message(:clear_selection, _bindings), do: "Clear selection"
  def message(:selected_items, _bindings), do: "Selected items"
  def message(:remove_chip, %{label: label}), do: "Remove #{label}"
  def message(:remove_icon, _bindings), do: "✕"
  def message(:clear_all, _bindings), do: "Clear all"
  def message(:selected_count, %{count: 0}), do: "No items selected"
  def message(:selected_count, %{count: 1}), do: "1 item selected"
  def message(:selected_count, %{count: count}), do: "#{count} items selected"
  def message(:max_selections_reached, %{max: max}), do: "Maximum of #{max} selections reached"
  def message(:keyboard_shortcut_hint, %{chord: chord}), do: "Keyboard shortcut: #{chord}"
  def message(:facet_key_context, _bindings), do: "Typing a facet name"
  def message(:facet_value_context, %{facet: facet}), do: "Typing a value for #{facet}"
  def message(:free_text_context, _bindings), do: "Typing free text"
  def message(:facet_key_suggestions_count, %{count: 0}), do: "No matching facets"
  def message(:facet_key_suggestions_count, %{count: 1}), do: "1 matching facet"
  def message(:facet_key_suggestions_count, %{count: count}), do: "#{count} matching facets"
  def message(:facet_value_suggestions_count, %{count: 0}), do: "No matching values"
  def message(:facet_value_suggestions_count, %{count: 1}), do: "1 matching value"
  def message(:facet_value_suggestions_count, %{count: count}), do: "#{count} matching values"
  def message(:facet_search_placeholder, _bindings), do: "Filter... (try status:active)"
  def message(:palette_label, _bindings), do: "Command palette"
  def message(:close_palette, _bindings), do: "Close"
  def message(:footer_navigate_hint, _bindings), do: "navigate"
  def message(:footer_select_hint, _bindings), do: "select"
  def message(:footer_close_hint, _bindings), do: "close"
end
