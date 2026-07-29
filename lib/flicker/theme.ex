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
    * `:facet_editor` — Spec 019 facet-editor part.
    * `:facet_editor_header` — Spec 019 facet-editor part.
    * `:facet_editor_body` — Spec 019 facet-editor part.
    * `:facet_editor_footer` — Spec 019 facet-editor part.
    * `:facet_editor_sheet` — the bottom-sheet variant of the pop-out. The
      shipped framework presets fold the sheet behaviour into `:facet_editor`
      itself with `max-sm:` utilities, since a 252px calendar in a dropdown is
      unusable on a phone; this part exists for a `vanilla` host that wants to
      target the sheet with its own CSS.
    * `:preset_rail` — Spec 019 facet-editor part.
    * `:preset_group_label` — Spec 019 facet-editor part.
    * `:preset_row` — Spec 019 facet-editor part.
    * `:preset_row_selected` — Spec 019 facet-editor part.
    * `:preset_row_range` — Spec 019 facet-editor part.
    * `:calendar` — Spec 019 facet-editor part.
    * `:calendar_nav` — Spec 019 facet-editor part.
    * `:calendar_nav_button` — Spec 019 facet-editor part.
    * `:calendar_month_label` — Spec 019 facet-editor part.
    * `:calendar_weekday` — Spec 019 facet-editor part.
    * `:calendar_grid` — Spec 019 facet-editor part.
    * `:calendar_day` — Spec 019 facet-editor part.
    * `:calendar_day_today` — Spec 019 facet-editor part.
    * `:calendar_day_selected` — Spec 019 facet-editor part.
    * `:calendar_day_in_range` — Spec 019 facet-editor part.
    * `:calendar_day_edge` — Spec 019 facet-editor part.
    * `:calendar_day_disabled` — Spec 019 facet-editor part.
    * `:dial` — Spec 019 facet-editor part.
    * `:dial_track` — Spec 019 facet-editor part.
    * `:dial_fill` — Spec 019 facet-editor part.
    * `:dial_thumb` — Spec 019 facet-editor part.
    * `:dial_input` — Spec 019 facet-editor part.
    * `:dial_value_label` — Spec 019 facet-editor part.
    * `:switch` — Spec 019 facet-editor part.
    * `:switch_thumb` — Spec 019 facet-editor part.
    * `:switch_on` — Spec 019 facet-editor part.
    * `:editor_error` — Spec 019 facet-editor part.
    * `:facet_count` — the match count rendered beside a facet value
      (Spec 021).
    * `:facet_count_zero` — added to a value row whose count is `0`. Dimmed
      rather than hidden, and still selectable: hiding it answers "why did that
      option disappear?" with silence, where `0` answers it.
    * `:facet_pill_invalid` — a committed-facet pill whose value failed to
      cast (Spec 023). Carries the error styling; the message itself renders in
      `:facet_error_message`, never as a tooltip.
    * `:facet_error_message` — the visible reason text beside an invalid pill.
    * `:facet_error_icon` — the error glyph, so the state is never signalled by
      colour alone.
    * `:facet_correction` — a suggested replacement value ("did you mean...").
    * `:facet_correction_accept` — the accept affordance on the top suggestion.
    * `:dispatch_blocked` — the visible "filter not applied" state under
      `on_invalid: :require`.
    * `:results_stale` — added to the listbox while a new search is in
      flight *and* previous results are still on screen (Spec 020). The
      previous set stays rendered rather than the list emptying and refilling;
      this part is what marks it as not-yet-current.
    * `:dispatch_hint` — the "press Enter to search" affordance shown
      beside the input while `dispatch: :enter` holds undispatched text
      (Spec 020). Also the target of the input's `aria-describedby` in that
      state.
    * `:hint` — the "keep typing to narrow results" / min-chars hint row;
      also the tail row shown once a `paginate`-d list hits `max_windows`
      or a provider ignoring `:offset` is detected (Spec 010) — windowing
      degrades into this same hint rather than a separate one.
    * `:loading_more` — `paginate`-d select only (Spec 010): the themed row
      rendered at the listbox tail while the next window loads.
    * `:chip_list` — multi-select: the wrapper around the selected chips.
    * `:chip` — multi-select: a single selected-value chip.
    * `:chip_remove` — multi-select: the per-chip remove button.
    * `:multi_field` — the bordered field box that holds tokens (multi-select
      chips, or `Flicker.search/1`'s committed facet pills) and the text
      input together, so the tokens sit *inside* the input, not above it.
      Replaces `:wrapper`+`:search_input`'s border for those cases.
    * `:multi_input` — the borderless text input inside `:multi_field` (the
      box owns the border; the input just grows to fill).
    * `:multi_clear` — multi-select: the "clear all" button inside
      `:multi_field`, vertically centred in the box (in normal flow, unlike
      the single-select `:clear_button` which overlays its input).
    * `:facet_pill_list` — `Flicker.search/1` (Spec 012): the wrapper around
      the committed-facet pills inside `:multi_field`.
    * `:facet_pill` — `Flicker.search/1`: a single committed-facet pill. Its
      field name is exposed on hover (a `title`) rather than always shown.
    * `:facet_pill_field` — the pill's small field label (e.g. "Status"),
      shown *without* a colon so the pill reads as a labelled value rather
      than as the `key:value` text it came from (Spec 012).
    * `:facet_pill_value` — the pill's primary value label (e.g. "Active").
    * `:facet_pill_remove` — the pill's remove (`×`) button.
    * `:selected_stack` — multi-select with a `:selected` slot (Spec 013): the
      container around the custom-rendered selected items (e.g. an avatar
      stack); replaces `:chip_list` when a `:selected` slot is given.
    * `:selected_item` — the per-item wrapper inside `:selected_stack`
      (positioning context for its remove control).
    * `:selected_overflow` — the "+N" token shown when the selection exceeds
      `max_visible`.
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
    * `:footer_hint` — `Flicker.palette/1`: the individual `<kbd>` chips
      inside the footer (↑↓/↵/esc). Distinct from `:kbd_hint`, which
      overlays the select input and is absolutely positioned — the footer
      chips sit in normal flow, so reusing `:kbd_hint` piled them all at the
      panel's right edge.
    * `:palette_close` — `Flicker.palette/1`: the panel's close control.
      Distinct from `:clear_button` (which overlays the select input, absolute
      positioned) so the close control doesn't land on top of the palette
      input.

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
          facet_editor: String.t(),
          facet_editor_header: String.t(),
          facet_editor_body: String.t(),
          facet_editor_footer: String.t(),
          facet_editor_sheet: String.t(),
          preset_rail: String.t(),
          preset_group_label: String.t(),
          preset_row: String.t(),
          preset_row_selected: String.t(),
          preset_row_range: String.t(),
          calendar: String.t(),
          calendar_nav: String.t(),
          calendar_nav_button: String.t(),
          calendar_month_label: String.t(),
          calendar_weekday: String.t(),
          calendar_grid: String.t(),
          calendar_day: String.t(),
          calendar_day_today: String.t(),
          calendar_day_selected: String.t(),
          calendar_day_in_range: String.t(),
          calendar_day_edge: String.t(),
          calendar_day_disabled: String.t(),
          dial: String.t(),
          dial_track: String.t(),
          dial_fill: String.t(),
          dial_thumb: String.t(),
          dial_input: String.t(),
          dial_value_label: String.t(),
          switch: String.t(),
          switch_thumb: String.t(),
          switch_on: String.t(),
          editor_error: String.t(),
          facet_count: String.t(),
          facet_count_zero: String.t(),
          facet_pill_invalid: String.t(),
          facet_error_message: String.t(),
          facet_error_icon: String.t(),
          facet_correction: String.t(),
          facet_correction_accept: String.t(),
          dispatch_blocked: String.t(),
          results_stale: String.t(),
          dispatch_hint: String.t(),
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
          footer: String.t(),
          footer_hint: String.t(),
          palette_close: String.t(),
          multi_field: String.t(),
          multi_input: String.t(),
          multi_clear: String.t(),
          facet_pill_list: String.t(),
          facet_pill: String.t(),
          facet_pill_field: String.t(),
          facet_pill_value: String.t(),
          facet_pill_remove: String.t(),
          selected_stack: String.t(),
          selected_item: String.t(),
          selected_overflow: String.t()
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
            facet_editor: "flicker-facet-editor",
            facet_editor_header: "flicker-facet-editor-header",
            facet_editor_body: "flicker-facet-editor-body",
            facet_editor_footer: "flicker-facet-editor-footer",
            facet_editor_sheet: "flicker-facet-editor-sheet",
            preset_rail: "flicker-preset-rail",
            preset_group_label: "flicker-preset-group-label",
            preset_row: "flicker-preset-row",
            preset_row_selected: "flicker-preset-row-selected",
            preset_row_range: "flicker-preset-row-range",
            calendar: "flicker-calendar",
            calendar_nav: "flicker-calendar-nav",
            calendar_nav_button: "flicker-calendar-nav-button",
            calendar_month_label: "flicker-calendar-month-label",
            calendar_weekday: "flicker-calendar-weekday",
            calendar_grid: "flicker-calendar-grid",
            calendar_day: "flicker-calendar-day",
            calendar_day_today: "flicker-calendar-day-today",
            calendar_day_selected: "flicker-calendar-day-selected",
            calendar_day_in_range: "flicker-calendar-day-in-range",
            calendar_day_edge: "flicker-calendar-day-edge",
            calendar_day_disabled: "flicker-calendar-day-disabled",
            dial: "flicker-dial",
            dial_track: "flicker-dial-track",
            dial_fill: "flicker-dial-fill",
            dial_thumb: "flicker-dial-thumb",
            dial_input: "flicker-dial-input",
            dial_value_label: "flicker-dial-value-label",
            switch: "flicker-switch",
            switch_thumb: "flicker-switch-thumb",
            switch_on: "flicker-switch-on",
            editor_error: "flicker-editor-error",
            facet_count: "flicker-facet-count",
            facet_count_zero: "flicker-facet-count-zero",
            facet_pill_invalid: "flicker-facet-pill-invalid",
            facet_error_message: "flicker-facet-error-message",
            facet_error_icon: "flicker-facet-error-icon",
            facet_correction: "flicker-facet-correction",
            facet_correction_accept: "flicker-facet-correction-accept",
            dispatch_blocked: "flicker-dispatch-blocked",
            results_stale: "flicker-results-stale",
            dispatch_hint: "flicker-dispatch-hint",
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
            footer: "flicker-footer",
            footer_hint: "flicker-footer-hint",
            palette_close: "flicker-palette-close",
            multi_field: "flicker-multi-field",
            multi_input: "flicker-multi-input",
            multi_clear: "flicker-multi-clear",
            facet_pill_list: "flicker-facet-pill-list",
            facet_pill: "flicker-facet-pill",
            facet_pill_field: "flicker-facet-pill-field",
            facet_pill_value: "flicker-facet-pill-value",
            facet_pill_remove: "flicker-facet-pill-remove",
            selected_stack: "flicker-selected-stack",
            selected_item: "flicker-selected-item",
            selected_overflow: "flicker-selected-overflow"

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
      clear_button: "absolute inset-y-0 right-2 flex cursor-pointer items-center text-gray-400 hover:text-gray-600",
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
      facet_editor:
        "z-40 flex border border-gray-200 bg-white shadow-lg max-sm:fixed max-sm:inset-x-0 max-sm:bottom-0 max-sm:flex-col max-sm:rounded-t-xl max-sm:p-1 sm:absolute sm:mt-1 sm:rounded-md",
      facet_editor_header: "flex items-center justify-between border-b border-gray-200 px-3 py-2 text-sm font-medium",
      facet_editor_body: "flex gap-4 p-3",
      facet_editor_footer: "mt-3 flex items-center justify-between border-t border-gray-200 pt-2 text-xs text-gray-500",
      facet_editor_sheet: "fixed inset-x-0 bottom-0 z-40 rounded-t-xl border-t border-gray-200 bg-white p-4 shadow-lg",
      preset_rail: "flex w-56 shrink-0 flex-col gap-0.5 overflow-y-auto border-r border-gray-200 pr-3",
      preset_group_label: "px-2 pb-1 text-[0.6875rem] font-semibold uppercase tracking-wide text-gray-500",
      preset_row:
        "flex w-full items-center justify-between gap-3 rounded px-2 py-1.5 text-left text-sm hover:bg-gray-50",
      preset_row_selected: "bg-indigo-50 font-medium text-indigo-700",
      preset_row_range: "shrink-0 text-xs text-gray-400",
      calendar: "w-64",
      calendar_nav: "mb-2 flex items-center justify-between",
      calendar_nav_button: "flex size-6 items-center justify-center rounded text-gray-500 hover:bg-gray-100",
      calendar_month_label: "text-sm font-semibold text-gray-900",
      calendar_weekday: "flex h-6 items-center justify-center text-[0.6875rem] font-semibold text-gray-500",
      calendar_grid: "grid grid-cols-7 gap-0.5",
      calendar_day: "flex size-8 items-center justify-center rounded-full text-sm hover:bg-gray-100",
      calendar_day_today: "ring-1 ring-indigo-500",
      calendar_day_selected: "bg-indigo-600 font-semibold text-white hover:bg-indigo-600",
      calendar_day_in_range: "bg-indigo-100 text-indigo-900",
      calendar_day_edge: "rounded-none",
      calendar_day_disabled: "size-8",
      dial: "relative h-8 w-full",
      dial_track: "absolute inset-x-0 top-1/2 h-1 -translate-y-1/2 rounded-full bg-gray-200",
      dial_fill: "absolute inset-y-0 rounded-full bg-indigo-500",
      dial_thumb:
        "absolute top-1/2 size-5 -translate-x-1/2 -translate-y-1/2 cursor-grab rounded-full border-2 border-white bg-indigo-600 shadow",
      dial_input: "w-24 rounded border border-gray-300 px-2 py-1 text-sm",
      dial_value_label: "mt-1 text-xs tabular-nums text-gray-600",
      switch: "relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full bg-gray-300 transition-colors",
      switch_thumb:
        "pointer-events-none absolute left-0.5 top-0.5 size-4 rounded-full bg-white shadow transition-transform",
      switch_on: "bg-indigo-600 [&>span]:translate-x-4",
      editor_error: "px-3 pb-2 text-xs text-red-700",
      facet_count: "ml-auto pl-3 text-xs tabular-nums text-gray-500",
      facet_count_zero: "opacity-50",
      facet_pill_invalid: "border border-red-300 bg-red-50 text-red-900",
      facet_error_message: "mt-1 text-xs text-red-700",
      facet_error_icon: "mr-1 inline-block text-red-600",
      facet_correction: "mt-1 text-xs text-gray-600",
      facet_correction_accept: "cursor-pointer font-medium text-indigo-600 underline hover:text-indigo-500",
      dispatch_blocked: "mt-1 text-xs font-medium text-red-700",
      results_stale: "opacity-60 transition-opacity",
      dispatch_hint: "mt-1 text-xs text-gray-500",
      hint: "px-3 py-2 text-xs text-gray-400",
      loading_more: "px-3 py-2 text-xs text-gray-400",
      chip_list: "flex flex-wrap gap-1",
      chip: "inline-flex items-center gap-1 rounded-full bg-indigo-50 px-2 py-1 text-xs text-indigo-700",
      chip_remove: "text-indigo-400 hover:text-indigo-700",
      kbd_hint:
        "pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 rounded border border-gray-300 px-1.5 text-xs text-gray-400",
      backdrop: "fixed inset-0 z-40 bg-gray-900/50",
      panel:
        "fixed left-1/2 top-24 z-50 w-full max-w-xl -translate-x-1/2 overflow-hidden rounded-lg bg-white shadow-2xl",
      palette_input:
        "w-full border-0 border-b border-gray-200 px-4 pb-4 pt-1 text-lg placeholder:text-gray-400 focus:outline-none",
      group_header: "px-3 py-1.5 text-xs font-semibold uppercase tracking-wide text-gray-400",
      footer: "flex items-center gap-4 border-t border-gray-100 px-4 py-2 text-xs text-gray-400",
      footer_hint: "rounded border border-gray-300 px-1.5 text-gray-500",
      palette_close: "rounded px-2 py-1 text-xs font-medium text-gray-400 hover:bg-gray-100 hover:text-gray-600",
      multi_field:
        "relative flex w-full flex-wrap items-center gap-1.5 rounded-md border border-gray-300 px-2 py-1.5 text-sm shadow-sm focus-within:border-indigo-500 focus-within:ring-1 focus-within:ring-indigo-500",
      multi_input:
        "min-w-[6rem] flex-1 border-0 bg-transparent p-0 text-sm placeholder:text-gray-400 focus:outline-none focus:ring-0",
      multi_clear: "ml-auto shrink-0 cursor-pointer self-center text-gray-400 hover:text-gray-600",
      facet_pill_list: "contents",
      facet_pill:
        "inline-flex items-center gap-1 rounded-md bg-indigo-50 py-1 pl-2 pr-1 text-sm text-indigo-900 focus-within:ring-2 focus-within:ring-indigo-400",
      facet_pill_field: "mr-1 text-[0.625rem] font-semibold uppercase tracking-wide opacity-70",
      facet_pill_value: "font-medium",
      facet_pill_remove:
        "rounded p-0.5 leading-none text-indigo-400 hover:bg-indigo-100 hover:text-indigo-700 focus:outline-none",
      selected_stack: "flex flex-wrap items-center gap-1",
      selected_item: "relative inline-flex items-center",
      selected_overflow:
        "inline-flex items-center rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600"
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
      # `relative` is explicit so the absolutely-positioned clear button and
      # keyboard hint anchor to the control even in daisyUI builds that don't
      # ship a `.dropdown { position: relative }` rule.
      wrapper: "dropdown relative w-full",
      search_input: "input input-bordered w-full",
      # Sized past the glyph and given its own hover/focus disc: at icon size
      # with only a colour shift the clear control reads as static text rather
      # than the button it is, and keyboard users get no focus affordance at
      # all (daisyUI's `.input` focus ring belongs to the input, not to this
      # overlaid sibling).
      clear_button:
        "absolute right-2 top-1/2 flex size-7 -translate-y-1/2 cursor-pointer items-center justify-center rounded-full text-lg leading-none text-base-content/50 transition-colors hover:bg-base-300 hover:text-base-content focus-visible:bg-base-300 focus-visible:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
      # `!w-full`/`!flex-nowrap` beat daisyUI's own `.menu` rules
      # (`width: fit-content` and `flex-wrap: wrap`) — without the `!`, an
      # overflowing result list wraps into extra columns and the dropdown
      # shrinks to its content width instead of filling the control.
      listbox:
        "menu dropdown-content menu-sm z-10 mt-1 max-h-60 !w-full !flex-nowrap overflow-auto rounded-box bg-base-100 p-2 shadow",
      # No `hover:bg-*` here: daisyUI's `menu` component (applied to the
      # listbox `<ul>`) already paints its own hover background on each
      # `<li>`'s interactive child (the option `<button>`) — adding a
      # second Tailwind `hover:bg-base-200` utility on the `<li>` itself
      # stacked a second, differently-positioned hover highlight on top of
      # daisyUI's own (BUG 4: double hover on option rows).
      #
      # The `active:!` pair *does* have to fight daisyUI: `.menu li > *:active`
      # paints the `--menu-active-bg` neutral colour, so holding the pointer
      # down on a result flashes the whole row near-black. An option is being
      # picked, not toggled into a selected menu item — keep the press looking
      # like the hover it continues.
      option: "cursor-pointer rounded-md px-3 py-2 active:!bg-base-content/10 active:!text-base-content",
      # Matches daisyUI's own `.menu` item hover background so keyboard-active
      # and pointer-hover look identical.
      option_active: "bg-base-content/10 text-base-content",
      option_label: "font-medium",
      option_sublabel: "ml-2 text-xs opacity-60",
      suggestion: "cursor-pointer rounded-md px-3 py-2",
      suggestion_token: "kbd kbd-sm mr-2",
      loading_state: "px-3 py-2 text-base-content/60",
      empty_state: "px-3 py-2 text-base-content/60",
      error_state: "px-3 py-2 text-error",
      facet_editor:
        "z-40 flex border border-base-300 bg-base-100 shadow-lg max-sm:fixed max-sm:inset-x-0 max-sm:bottom-0 max-sm:flex-col max-sm:rounded-t-box max-sm:p-1 sm:absolute sm:mt-1 sm:rounded-box",
      facet_editor_header: "flex items-center justify-between border-b border-gray-200 px-3 py-2 text-sm font-medium",
      facet_editor_body: "flex gap-4 p-3",
      facet_editor_footer: "mt-3 flex items-center justify-between border-t border-gray-200 pt-2 text-xs text-gray-500",
      facet_editor_sheet:
        "fixed inset-x-0 bottom-0 z-40 rounded-t-box border-t border-base-300 bg-base-100 p-4 shadow-lg",
      preset_rail: "flex w-56 shrink-0 flex-col gap-0.5 overflow-y-auto border-r border-gray-200 pr-3",
      preset_group_label: "px-2 pb-1 text-[0.6875rem] font-semibold uppercase tracking-wide text-gray-500",
      preset_row:
        "flex w-full items-center justify-between gap-3 rounded px-2 py-1.5 text-left text-sm hover:bg-gray-50",
      preset_row_selected: "bg-primary/10 font-medium text-primary",
      preset_row_range: "shrink-0 text-xs text-gray-400",
      calendar: "w-64",
      calendar_nav: "mb-2 flex items-center justify-between",
      calendar_nav_button: "flex size-6 items-center justify-center rounded text-gray-500 hover:bg-gray-100",
      calendar_month_label: "text-sm font-semibold text-gray-900",
      calendar_weekday: "flex h-6 items-center justify-center text-[0.6875rem] font-semibold text-gray-500",
      calendar_grid: "grid grid-cols-7 gap-0.5",
      calendar_day: "flex size-8 items-center justify-center rounded-full text-sm hover:bg-gray-100",
      calendar_day_today: "ring-1 ring-primary",
      calendar_day_selected: "bg-primary font-semibold text-primary-content",
      calendar_day_in_range: "bg-primary/15 text-base-content",
      calendar_day_edge: "rounded-none",
      calendar_day_disabled: "size-8",
      dial: "relative h-8 w-full",
      dial_track: "absolute inset-x-0 top-1/2 h-1 -translate-y-1/2 rounded-full bg-gray-200",
      dial_fill: "absolute inset-y-0 rounded-full bg-primary",
      dial_thumb:
        "absolute top-1/2 size-5 -translate-x-1/2 -translate-y-1/2 cursor-grab rounded-full border-2 border-base-100 bg-primary shadow",
      dial_input: "input input-bordered input-sm w-24",
      dial_value_label: "mt-1 text-xs tabular-nums text-gray-600",
      switch: "toggle",
      switch_thumb: "sr-only",
      switch_on: "toggle-primary",
      editor_error: "px-3 pb-2 text-xs text-error",
      facet_count: "ml-auto pl-3 text-xs tabular-nums text-base-content/60",
      facet_count_zero: "opacity-50",
      facet_pill_invalid: "badge badge-error badge-outline",
      facet_error_message: "mt-1 text-xs text-error",
      facet_error_icon: "mr-1 inline-block text-error",
      facet_correction: "mt-1 text-xs text-base-content/70",
      facet_correction_accept: "link link-primary cursor-pointer font-medium",
      dispatch_blocked: "mt-1 text-xs font-medium text-error",
      results_stale: "opacity-60 transition-opacity",
      dispatch_hint: "mt-1 text-xs text-base-content/60",
      hint: "px-3 py-2 text-xs text-base-content/50",
      loading_more: "px-3 py-2 text-xs text-base-content/50",
      chip_list: "flex flex-wrap gap-1",
      chip: "badge badge-primary gap-1",
      chip_remove: "cursor-pointer",
      kbd_hint: "pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-xs text-base-content/40",
      backdrop: "fixed inset-0 z-40 bg-black/40",
      panel: "modal-box fixed left-1/2 top-24 z-50 w-full max-w-xl -translate-x-1/2 p-0",
      palette_input: "input input-ghost w-full border-0 border-b border-base-200 text-base focus:outline-none",
      group_header: "px-3 py-1.5 text-xs font-semibold uppercase tracking-wide text-base-content/50",
      footer: "flex items-center gap-4 border-t border-base-200 px-4 py-2 text-xs text-base-content/50",
      footer_hint: "kbd kbd-sm",
      palette_close: "btn btn-ghost btn-xs",
      multi_field: "input input-bordered flex h-auto w-full flex-wrap items-center gap-1.5 py-1.5",
      multi_input: "min-w-[6rem] flex-1 border-0 bg-transparent p-0 focus:outline-none",
      multi_clear: "ml-auto shrink-0 self-center cursor-pointer",
      facet_pill_list: "contents",
      facet_pill:
        "inline-flex items-center gap-1 rounded-md bg-primary/10 py-1 pl-2 pr-1 text-sm text-primary focus-within:ring-2 focus-within:ring-primary/50",
      facet_pill_field: "mr-1 text-[0.625rem] font-semibold uppercase tracking-wide opacity-70",
      facet_pill_value: "font-medium",
      facet_pill_remove:
        "rounded p-0.5 leading-none text-primary/60 hover:bg-primary/20 hover:text-primary focus:outline-none",
      selected_stack: "flex flex-wrap items-center gap-1",
      selected_item: "relative inline-flex items-center",
      selected_overflow: "badge badge-neutral badge-sm"
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
