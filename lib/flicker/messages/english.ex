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
    * `:invalid_<reason>` — one per validation reason a facet value can fail
      with (Spec 018, ADR-012): `:invalid_integer`, `:invalid_float`,
      `:invalid_boolean`, `:invalid_date`, `:invalid_datetime`,
      `:invalid_duration`, `:invalid_range`, `:invalid_incomplete_range`,
      `:invalid_reversed_range`, `:invalid_incomplete_list`,
      `:invalid_not_in_values` (%{values: [...]}), `:invalid_out_of_bounds`
      (%{min:, max:}), `:invalid_constraint_violation` (%{message:}),
      `:invalid_custom` (%{message:}), and `:invalid_value` as the catch-all
      for a reason this module doesn't know. Rendered against the invalid
      facet pill; the parser itself never produces English.
    * `:dispatch_blocked` — shown, and announced, when `on_invalid: :require`
      is withholding the query because a facet value is invalid (Spec 023).
    * `:did_you_mean` — %{label: name} — the top correction suggestion.
    * `:apply_fix` — the accept affordance for a mechanical fix (a reversed
      range's swap, an out-of-bounds clamp).
    * `:invalid_facet` — %{key: key} — the accessible name for an invalid
      facet pill.
    * `:edit_facet` — %{label: name} — `aria-label` for the control that
      reopens a committed facet's editor (Spec 019).
    * `:facet_editor_opened` — %{label: name} — the live-region announcement
      when a facet editor's pop-out opens (Spec 019), naming the facet and the
      fact that it is a dialog, since entering a modal sub-context must be
      audible and not merely visible.
    * `:close_facet_editor`, `:preset_group_suggested`, `:previous_month`,
      `:next_month`, `:range_from`, `:range_to`, `:facet_values`,
      `:facet_editor_done`, `:pick_an_end_date` — every visible string inside a
      Spec 019 facet editor. Routed through here rather than hardcoded so the
      key list stays the complete, auditable inventory of user-facing text
      (ADR-009, and Spec 007's "a grep for literals in templates finds none").
    * `:active_filters` — `aria-label` for the committed-facet pill row in
      `Flicker.select/1` (Spec 015), naming it as filters rather than as the
      selection chips beside it.
    * `:press_enter_to_search` — shown, and referenced by the input's
      `aria-describedby`, while `dispatch: :enter` holds typed text that
      hasn't been searched yet (Spec 020). A search box that has silently
      stopped searching is a broken search box, so this state is always
      both visible and announced.
    * `:results_count` — %{count: n} — the live-region announcement after
      results update.
    * `:item_selected` — %{label: name} — the live-region announcement after
      a single-select selection is made, naming the selected item.
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
    * `:loading_more` — `paginate`-d select only (Spec 010): shown in the
      themed tail row while the next window loads.
    * `:more_results_appended` — %{count: n, total: total} — `paginate`-d
      select only: the live-region announcement after a window appends
      (Spec 010), naming how many were just added and the new running
      total.
  """
  @spec message(atom(), map()) :: String.t()
  def message(:search_placeholder, _bindings), do: "Search..."
  def message(:loading, _bindings), do: "Loading..."
  def message(:no_results, _bindings), do: "No results found"
  def message(:error, _bindings), do: "Something went wrong. Please try again."
  def message(:keep_typing, _bindings), do: "Keep typing to narrow results..."

  def message(:min_chars_hint, %{min_chars: min_chars}), do: "Type at least #{min_chars} characters to search"

  def message(:press_enter_to_search, _bindings), do: "Press Enter to search"

  def message(:invalid_integer, _bindings), do: "must be a whole number"
  def message(:invalid_float, _bindings), do: "must be a number"
  def message(:invalid_boolean, _bindings), do: "must be true or false"
  def message(:invalid_date, _bindings), do: "expected a date like 2026-07-01, today, or 7d"
  def message(:invalid_datetime, _bindings), do: "expected a time like 2026-07-01T09:30:00Z"
  def message(:invalid_duration, _bindings), do: "expected a duration like 15m or 2h30m"
  def message(:invalid_range, _bindings), do: "expected a range like 2026-07-01..2026-07-31"
  def message(:invalid_incomplete_range, _bindings), do: "a range needs at least one endpoint"
  def message(:invalid_reversed_range, _bindings), do: "the start is after the end"

  def message(:invalid_incomplete_list, _bindings), do: "remove the trailing comma, or add another value"

  # Each parameterised `:invalid_*` key ends in a clause that ignores its
  # bindings. A caller assembling params by hand can omit a key, and a message
  # module that raises for its *own* documented key takes the render down —
  # `Flicker.Messages.get/3`'s rescue only covers a module that doesn't
  # implement the key at all, not one that implements it too narrowly.
  def message(:invalid_not_in_values, %{values: [_ | _] = values}) do
    "must be one of: " <> Enum.map_join(values, ", ", &to_string/1)
  end

  def message(:invalid_not_in_values, _bindings), do: "is not one of the allowed values"

  def message(:invalid_out_of_bounds, %{min: nil, max: max}) when not is_nil(max), do: "must be at most #{max}"

  def message(:invalid_out_of_bounds, %{min: min, max: nil}) when not is_nil(min), do: "must be at least #{min}"

  def message(:invalid_out_of_bounds, %{min: min, max: max}) when not is_nil(min) and not is_nil(max),
    do: "must be between #{min} and #{max}"

  def message(:invalid_out_of_bounds, _bindings), do: "is out of range"

  def message(:invalid_constraint_violation, %{message: message}) when is_binary(message), do: message

  def message(:invalid_constraint_violation, _bindings), do: "is not valid"
  def message(:invalid_custom, %{message: message}) when is_binary(message), do: message
  def message(:invalid_custom, _bindings), do: "is not valid"
  def message(:invalid_value, _bindings), do: "is not valid"
  def message(:dispatch_blocked, _bindings), do: "Filter not applied — fix the highlighted facet"
  def message(:did_you_mean, %{label: label}), do: "Did you mean #{label}?"
  def message(:apply_fix, _bindings), do: "Fix it"
  def message(:invalid_facet, %{key: key}), do: "#{key} is not valid"
  def message(:edit_facet, %{label: label}), do: "Edit #{label}"
  def message(:active_filters, _bindings), do: "Active filters"
  def message(:facet_editor_opened, %{label: label}), do: "#{label} editor, dialog"
  def message(:close_facet_editor, _bindings), do: "Close"
  def message(:preset_group_suggested, _bindings), do: "Suggested"
  def message(:previous_month, _bindings), do: "Previous month"
  def message(:next_month, _bindings), do: "Next month"
  def message(:range_from, _bindings), do: "From"
  def message(:range_to, _bindings), do: "To"
  def message(:facet_values, _bindings), do: "Values"
  def message(:facet_editor_done, _bindings), do: "Done"
  def message(:pick_an_end_date, _bindings), do: "pick an end date"

  def message(:results_count, %{count: 0}), do: "No results available"
  def message(:results_count, %{count: 1}), do: "1 result available"
  def message(:results_count, %{count: count}), do: "#{count} results available"
  def message(:item_selected, %{label: label}), do: "#{label} selected"
  def message(:clear_selection, _bindings), do: "Clear selection"
  def message(:change_selection, _bindings), do: "Change selection"
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
  def message(:selected_overflow, %{count: count}), do: "#{count} more selected"
  def message(:facet_search_placeholder, _bindings), do: "Filter... (try status:active)"
  def message(:facet_free_value_hint, _bindings), do: "Type a value, then Space to add"

  def message(:facet_date_value_hint, _bindings), do: "Type a date (YYYY-MM-DD), then Space to add"

  def message(:palette_label, _bindings), do: "Command palette"
  def message(:close_palette, _bindings), do: "Close"
  def message(:footer_navigate_hint, _bindings), do: "navigate"
  def message(:footer_select_hint, _bindings), do: "select"
  def message(:footer_close_hint, _bindings), do: "close"
  def message(:loading_more, _bindings), do: "Loading more..."

  def message(:more_results_appended, %{count: 1, total: total}), do: "1 more result, #{total} total"

  def message(:more_results_appended, %{count: count, total: total}), do: "#{count} more results, #{total} total"
end
