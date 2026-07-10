defmodule Flicker.Components.Select do
  @moduledoc """
  The internal `Phoenix.LiveComponent` behind `Flicker.select/1`.

  This module is not part of the public API — hosts never reference it
  directly, its assigns and events are internal, and its shape can change
  between minor releases without notice. `Flicker.select/1` is the only
  supported entry point.

  Owns all search state: the typed query, the loaded results, the open/
  closed listbox, the resolved selection, and (in form-field mode) the
  hidden inputs and `_unused_<field>` recovery marker (ADR-005, ported
  verbatim per the extraction notes). Every render is gated on
  `connected?/1` — interactive controls are disabled until the socket has
  joined, so typing before the LiveSocket connects can never be lost.

  `multiple` (Spec 002) switches the value model: `selected` becomes a list
  of `Flicker.Result` structs (kept as Results, not bare values, so chips
  render without refetching) instead of a single Result or `nil`. Options
  already in `selected` are excluded from search results; `fetch/2` still
  runs exactly once, resolving every preselected value in one call
  (ADR-003) regardless of how many are set.

  `group` (Spec 008): when any `Flicker.Result` in `results` carries a
  `:group`, the listbox renders a contiguous, non-interactive
  `theme.group_header` row before the first result of each new group —
  ordering is whatever the provider returned, never re-sorted here. A
  groupless result list (every `:group` is `nil`, the default) renders
  exactly as it always has; `Flicker.select/1` never sets `:group` itself,
  it only renders it when a provider does — `Flicker.palette/1` is the
  only caller that has any special interest in it, and even that interest
  lives entirely in provider data, not a branch here.

  `navigate_on_select` (Spec 008, internal-only assign — not part of
  `Flicker.select/1`'s public attrs) additionally issues a `push_navigate/2`
  to `result.meta.href` on selection, when set. This is `Flicker.palette/1`'s
  navigate-on-select convention; it is plain assign-driven behaviour, not a
  branch on "am I a palette" — `Flicker.select/1` simply never sets the
  assign, so its own selections never navigate.

  `facets` (Spec 003) drives the same `Flicker.CursorContext`/
  `Flicker.FacetSuggest` machinery `Flicker.Components.Search` does: while
  the cursor sits in facet-key or facet-value position, the listbox shows
  key/value suggestions (tagged `meta.flicker_facet: true`) instead of
  record results, and picking one edits the typed text rather than
  selecting a record. Once the cursor is back in free-text position, the
  listbox reverts to ordinary record search — run against the free-text
  portion `Flicker.Query.parse/2` extracts, not the raw typed string (so a
  completed `status:active` doesn't leak into the `ilike` match). v1 scope
  note: the parsed facet filter narrows the *autocomplete UX* only — it is
  not yet AND-ed into the provider's own record query (recorded as a
  follow-up in Spec 003's open questions).
  """

  use Phoenix.LiveComponent

  alias Flicker.{FacetSuggest, Keyboard, Messages, Provider, Query, Result}

  require Logger

  @default_limit 25
  @default_min_chars 0

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:results, fn -> [] end)
      |> assign_new(:has_more, fn -> false end)
      |> assign_new(:open, fn -> false end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:error, fn -> false end)
      |> assign_new(:multiple, fn -> false end)
      |> assign_new(:max_selections, fn -> nil end)
      |> assign_new(:activate_with_keyboard, fn -> nil end)
      |> assign_new(:facets, fn -> [] end)
      |> assign_new(:facet_context, fn -> :text end)
      |> assign_new(:navigate_on_select, fn -> false end)

    socket =
      socket
      |> assign_new(:selected, fn -> if socket.assigns.multiple, do: [] end)
      |> assign_new(:limit, fn -> @default_limit end)
      |> assign_new(:min_chars, fn -> @default_min_chars end)
      |> assign(:connected?, Phoenix.LiveView.connected?(socket))
      |> resolve_selected()

    {:ok, socket}
  end

  @impl true
  def handle_event("focus", _params, socket) do
    socket =
      if socket.assigns.open do
        socket
      else
        # Re-run the search against whatever text is already in the input
        # (blank, previously typed, or a resolved selection's label) rather
        # than blanking it — Escape closes the listbox "keeping input text"
        # and ArrowDown only opens the listbox, neither should discard it.
        apply_query(socket, socket.assigns.query)
      end

    {:noreply, push_event(socket, "focusElementById", %{id: input_id(socket)})}
  end

  def handle_event("query", %{"value" => text}, socket) do
    if text == socket.assigns.query do
      {:noreply, socket}
    else
      {:noreply, socket |> clear_stale_selection(text) |> apply_query(text)}
    end
  end

  def handle_event("select", %{"value" => raw_value}, socket) do
    result = Enum.find(socket.assigns.results, &(to_string(&1.value) == raw_value))
    select_result(result, raw_value, socket)
  end

  def handle_event("remove_chip", %{"value" => raw_value}, %{assigns: %{multiple: true}} = socket) do
    new_selected = Enum.reject(socket.assigns.selected, &(to_string(&1.value) == raw_value))

    socket =
      socket
      |> assign(selected: new_selected)
      |> notify_multi_selection(new_selected)

    {:noreply, push_event(socket, "focusElementById", %{id: input_id(socket)})}
  end

  def handle_event("remove_last_chip", _params, %{assigns: %{multiple: true, selected: [_ | _] = selected}} = socket) do
    new_selected = List.delete_at(selected, -1)

    socket =
      socket
      |> assign(selected: new_selected)
      |> notify_multi_selection(new_selected)

    {:noreply, socket}
  end

  def handle_event("remove_last_chip", _params, socket), do: {:noreply, socket}

  def handle_event("clear", _params, %{assigns: %{multiple: true}} = socket) do
    socket =
      socket
      |> assign(selected: [], query: "", open: false)
      |> notify_multi_selection([])

    {:noreply, push_event(socket, "focusElementById", %{id: input_id(socket)})}
  end

  def handle_event("clear", _params, socket) do
    socket =
      socket
      |> assign(selected: nil, query: "", open: false)
      |> notify_selection(nil)

    {:noreply, push_event(socket, "focusElementById", %{id: input_id(socket)})}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, open: false)}
  end

  def handle_event("escape", _params, socket) do
    cond do
      socket.assigns.open ->
        {:noreply, assign(socket, open: false)}

      socket.assigns.query != "" ->
        {:noreply, socket |> assign(query: "") |> run_search("")}

      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_async(:search, {:ok, {:ok, results}}, socket) do
    limit = socket.assigns.limit
    available = filter_available(results, socket)

    {:noreply,
     assign(socket,
       results: Enum.take(available, limit),
       has_more: length(available) > limit,
       loading: false,
       error: false
     )}
  end

  def handle_async(:search, {:ok, {:error, reason}}, socket) do
    Logger.warning("Flicker search failed: #{inspect(reason)}")
    {:noreply, assign(socket, results: [], has_more: false, loading: false, error: true)}
  end

  # `cancel_async/2`'s default exit reason — the synchronous facet branches
  # of `run_faceted_search/2` cancel a stale in-flight record search this
  # way before assigning their own results. `Process.exit/2` kills the task
  # but doesn't un-track its ref, so this callback still runs once the
  # kill signal lands; without this clause it would clobber the
  # just-rendered facet results with an error state a moment later. Any
  # other exit reason is a genuine crash, still surfaced as an error.
  def handle_async(:search, {:exit, {:shutdown, :cancel}}, socket), do: {:noreply, socket}

  def handle_async(:search, {:exit, reason}, socket) do
    Logger.warning("Flicker search task exited: #{inspect(reason)}")
    {:noreply, assign(socket, results: [], has_more: false, loading: false, error: true)}
  end

  defp select_result(%Result{meta: %{flicker_facet: true, insert: insert}}, _raw_value, socket) do
    new_text = FacetSuggest.replace_current_token(socket.assigns.query, insert)

    {:noreply, push_event(apply_query(socket, new_text), "focusElementById", %{id: input_id(socket)})}
  end

  defp select_result(result, _raw_value, %{assigns: %{multiple: true}} = socket) do
    socket =
      if result && addable?(socket) do
        new_selected = socket.assigns.selected ++ [result]

        socket
        |> assign(selected: new_selected)
        |> update_results(&filter_selected(&1, new_selected))
        |> notify_multi_selection(new_selected)
      else
        socket
      end

    {:noreply, push_event(socket, "focusElementById", %{id: input_id(socket)})}
  end

  # `result` is nil when the clicked value no longer matches anything in
  # `@results` (async results landed, or the facet context flipped, between
  # render and click) — a no-op rather than clearing whatever was already
  # selected, mirroring the `multiple: true` clause's `if result && ...`
  # guard above.
  defp select_result(nil, _raw_value, socket), do: {:noreply, socket}

  defp select_result(result, _raw_value, socket) do
    socket =
      socket
      |> assign(selected: result, query: display_text(result), open: false)
      |> notify_selection(result)
      |> maybe_navigate(result)

    {:noreply, socket}
  end

  # Spec 008's navigate-on-select convention: `meta.href` is generic
  # `Flicker.Result` data, and `navigate_on_select` is a generic assign
  # `Flicker.select/1` never sets — `Flicker.palette/1` is the only caller
  # that turns it on, but this code has no idea a palette exists.
  defp maybe_navigate(%{assigns: %{navigate_on_select: true}} = socket, %Result{meta: %{href: href}})
       when is_binary(href) do
    push_navigate(socket, to: href)
  end

  defp maybe_navigate(socket, _result), do: socket

  # Spec 001's keyboard map ("single, selection present | Backspace | clear
  # the selection, returns to searchable state") generalises to any edit
  # that diverges the typed text from the selected label, not just
  # Backspace specifically — otherwise the hidden input keeps carrying the
  # old value while the visible input shows different text, and a form
  # submitted at that point silently sends the stale selection.
  defp clear_stale_selection(%{assigns: %{multiple: false, selected: %Result{} = result}} = socket, text) do
    if text == display_text(result) do
      socket
    else
      socket |> assign(selected: nil) |> notify_selection(nil)
    end
  end

  defp clear_stale_selection(socket, _text), do: socket

  defp apply_query(socket, text) do
    trimmed = String.trim(text)
    socket = assign(socket, query: text, open: true)

    cond do
      trimmed == "" ->
        run_search(socket, "")

      String.length(trimmed) < socket.assigns.min_chars ->
        socket
        |> cancel_async(:search)
        |> assign(results: [], has_more: false, loading: false, error: false)

      true ->
        run_search(socket, trimmed)
    end
  end

  # `start_async/3` keyed on the same name (`:search`) is the stale-result
  # cancellation mechanism: "If there is an in-flight task with the same
  # name, the later start_async wins and the previous task's result is
  # ignored" — a slower response for an earlier keystroke can never
  # overwrite a newer one.
  defp run_search(%{assigns: %{facets: []}} = socket, text), do: run_record_search(socket, text)

  # Classifies off `socket.assigns.query` (the raw, untyped-through text
  # `apply_query/2` just assigned) rather than the `text` argument here —
  # the latter is trimmed for the plain-record-search path and trimming
  # would erase the trailing-space transition out of facet-value position
  # (`"status:active "` classifying as `:text`, not still `{:value, ...}`).
  defp run_search(socket, _trimmed_text) do
    context = FacetSuggest.classify(socket.assigns.query, socket.assigns.facets)
    socket = assign(socket, facet_context: context)
    run_faceted_search(socket, context)
  end

  # Facet-key position (`stat|`) — synchronous, no provider round-trip. A
  # bare word with no facet key matching it (an ordinary free-text word —
  # `Flicker.CursorContext` can't yet tell "typing a new facet key" from
  # "typing free text" until an operator or a non-matching prefix rules the
  # former out) falls back to an ordinary record search rather than an
  # empty listbox — free text still has to work while facets are configured.
  defp run_faceted_search(socket, {:key, prefix}) do
    case FacetSuggest.key_suggestions(prefix, socket.assigns.facets) do
      [] ->
        run_faceted_search(socket, :text)

      suggestions ->
        socket
        |> cancel_async(:search)
        |> assign(results: suggestions, has_more: false, loading: false, error: false)
    end
  end

  # Facet-value position for an enum facet — synchronous, closed picklist.
  defp run_faceted_search(socket, {:value, %{type: :enum} = facet, prefix}) do
    suggestions = FacetSuggest.enum_value_suggestions(facet, prefix)

    socket
    |> cancel_async(:search)
    |> assign(results: suggestions, has_more: false, loading: false, error: false)
  end

  # Facet-value position for a relationship facet — nested, actor-scoped
  # search over the related resource (Spec 003). A relationship facet's
  # `:related` is itself an Ash-only concept (ADR-006) —
  # `FacetSuggest.related_search/3` only compiles when `ash` is present, so
  # this clause only exists then too. Without `ash`, a relationship facet
  # can't be configured in the first place, so the no-picklist clause below
  # is the correct fallback rather than referencing an undefined function.
  if Code.ensure_loaded?(Ash) do
    defp run_faceted_search(socket, {:value, %{related: related} = facet, prefix}) when not is_nil(related) do
      actor = socket.assigns[:actor]
      tenant = socket.assigns[:tenant]
      fetch_limit = socket.assigns.limit + 1

      socket
      |> assign(loading: true, error: false)
      |> start_async(:search, fn ->
        FacetSuggest.related_search(facet, prefix,
          actor: actor,
          tenant: tenant,
          limit: fetch_limit
        )
      end)
    end
  end

  # A facet-value position with no picklist (plain string/numeric/date
  # facet) — no autocomplete source, keyboard behaviour reverts to "no
  # suggestions" until the value is complete and the cursor moves on.
  defp run_faceted_search(socket, {:value, _facet, _prefix}) do
    socket
    |> cancel_async(:search)
    |> assign(results: [], has_more: false, loading: false, error: false)
  end

  # Free-text position: an ordinary record search, but against the
  # free-text portion `Flicker.Query.parse/2` extracts — a completed
  # `status:active` token never leaks into the `ilike` match.
  defp run_faceted_search(socket, :text) do
    parsed_text = Query.parse(text_for_facet_parse(socket), socket.assigns.facets).text
    run_record_search(socket, parsed_text)
  end

  defp text_for_facet_parse(socket), do: socket.assigns.query

  defp run_record_search(socket, text) do
    provider = socket.assigns.provider
    actor = socket.assigns[:actor]
    tenant = socket.assigns[:tenant]
    # Fetch one more than we display: `has_more` without a count query
    # (extraction notes #3) — "keep typing to narrow" instead of paginating.
    fetch_limit = socket.assigns.limit + 1

    socket
    |> assign(loading: true, error: false)
    |> start_async(:search, fn ->
      Provider.run_search(provider, %Query{text: text},
        actor: actor,
        tenant: tenant,
        limit: fetch_limit
      )
    end)
  end

  defp resolve_selected(%{assigns: %{field: nil}} = socket), do: socket

  defp resolve_selected(%{assigns: %{multiple: true, field: field, selected: selected}} = socket) do
    values = field.value |> List.wrap() |> Enum.reject(&blank?/1)

    cond do
      values == [] ->
        assign(socket, selected: [])

      matches_values?(selected, values) ->
        socket

      true ->
        fetch_selected_multi(socket, values)
    end
  end

  defp resolve_selected(%{assigns: %{field: field, selected: selected}} = socket) do
    value = field.value

    cond do
      blank?(value) ->
        assign(socket, selected: nil)

      selected && to_string(selected.value) == to_string(value) ->
        socket

      true ->
        fetch_selected(socket, value)
    end
  end

  defp matches_values?(selected, values) do
    Enum.sort(Enum.map(selected, &to_string(&1.value))) ==
      Enum.sort(Enum.map(values, &to_string/1))
  end

  defp fetch_selected(socket, value) do
    provider = socket.assigns.provider
    actor = socket.assigns[:actor]
    tenant = socket.assigns[:tenant]

    case Provider.run_fetch(provider, [value], actor: actor, tenant: tenant) do
      {:ok, [result | _]} ->
        assign(socket, selected: result, query: display_text(result))

      {:ok, []} ->
        assign(socket, selected: nil)

      {:error, reason} ->
        Logger.warning("Flicker fetch failed: #{inspect(reason)}")
        assign(socket, selected: nil)
    end
  end

  # Resolves every preselected value in one `fetch/2` call (ADR-003) — an
  # edit form opening with N ids set never issues N queries. Values that
  # don't resolve (deleted records, or records a policy now hides) are
  # simply dropped rather than crashing the mount.
  defp fetch_selected_multi(socket, values) do
    provider = socket.assigns.provider
    actor = socket.assigns[:actor]
    tenant = socket.assigns[:tenant]

    case Provider.run_fetch(provider, values, actor: actor, tenant: tenant) do
      {:ok, results} ->
        assign(socket, selected: reorder_like(values, results))

      {:error, reason} ->
        Logger.warning("Flicker fetch failed: #{inspect(reason)}")
        assign(socket, selected: [])
    end
  end

  # Restores selection order (form/param order), and silently drops any
  # value `fetch/2` didn't resolve — a partial result is normal (ADR-003),
  # not something to render as an error or crash on.
  defp reorder_like(values, results) do
    by_value = Map.new(results, &{to_string(&1.value), &1})

    values
    |> Enum.map(&Map.get(by_value, to_string(&1)))
    |> Enum.reject(&is_nil/1)
  end

  defp update_results(socket, fun), do: assign(socket, results: fun.(socket.assigns.results))

  defp filter_available(results, %{assigns: %{multiple: true, selected: selected}}),
    do: filter_selected(results, selected)

  defp filter_available(results, _socket), do: results

  defp filter_selected(results, selected) do
    taken = MapSet.new(selected, &to_string(&1.value))
    Enum.reject(results, &MapSet.member?(taken, to_string(&1.value)))
  end

  defp addable?(%{assigns: %{max_selections: nil}}), do: true

  defp addable?(%{assigns: %{max_selections: max, selected: selected}}), do: length(selected) < max

  defp notify_multi_selection(socket, selected) do
    case {socket.assigns[:field], socket.assigns[:on_select]} do
      {nil, tag} when not is_nil(tag) ->
        send(self(), {tag, selected})
        socket

      {field, _} when not is_nil(field) ->
        values = Enum.map(selected, &to_string(&1.value))
        send(self(), {__MODULE__, :selected, field.name, values})
        socket

      _ ->
        socket
    end
  end

  defp notify_selection(socket, result) do
    case {socket.assigns[:field], socket.assigns[:on_select]} do
      {nil, tag} when not is_nil(tag) ->
        send(self(), {tag, result})
        socket

      {field, _} when not is_nil(field) ->
        value = result && to_string(result.value)
        send(self(), {__MODULE__, :selected, field.name, value})
        socket

      _ ->
        socket
    end
  end

  defp display_text(nil), do: ""
  defp display_text(%Result{label: label}), do: label

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp selected_value(nil), do: ""
  defp selected_value(%Result{value: value}), do: to_string(value)

  defp unused_marker_name(field), do: "#{field.form.name}[_unused_#{field.field}]"

  defp input_id(%Phoenix.LiveView.Socket{} = socket), do: input_id_for(socket.assigns.id)
  defp input_id(assigns), do: input_id_for(assigns.id)

  defp input_id_for(id), do: "#{id}-input"
  defp listbox_id_for(id), do: "#{id}-listbox"
  defp option_id(assigns, index), do: "#{assigns.id}-option-#{index}"

  defp message(assigns, key, bindings \\ %{}), do: Messages.get(assigns[:messages], key, bindings)

  # The single live-region announcement (Spec 007), derived from exactly the
  # assigns that drive the visual render — never a parallel "last announced"
  # assign that could drift from what's on screen. `run_search/2`'s
  # `start_async/3` same-name cancellation (see the comment there) already
  # guarantees `@results`/`@loading`/`@error` reflect only the latest query,
  # so deriving the announcement from them for free extends that guarantee
  # to announcements. Rapid keystrokes never queue a backlog of stale
  # announcements because the underlying state itself only changes as often
  # as `phx-debounce={@debounce}` lets a "query" event reach the server.
  defp announcement(assigns) do
    [state_announcement(assigns), selection_announcement(assigns)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp state_announcement(%{error: true} = assigns), do: message(assigns, :error)
  defp state_announcement(%{loading: true} = assigns), do: message(assigns, :loading)

  defp state_announcement(%{multiple: true, at_max: true} = assigns),
    do: message(assigns, :max_selections_reached, %{max: assigns.max_selections})

  defp state_announcement(%{open: true, facets: [_ | _], facet_context: context} = assigns),
    do: facet_state_announcement(assigns, context)

  defp state_announcement(%{open: true} = assigns),
    do: message(assigns, :results_count, %{count: length(assigns.results)})

  defp state_announcement(_assigns), do: ""

  defp facet_state_announcement(assigns, {:key, _prefix}) do
    [
      message(assigns, :facet_key_context),
      message(assigns, :facet_key_suggestions_count, %{count: length(assigns.results)})
    ]
    |> Enum.join(" ")
  end

  defp facet_state_announcement(assigns, {:value, facet, _prefix}) do
    [
      message(assigns, :facet_value_context, %{facet: facet_label(facet)}),
      message(assigns, :facet_value_suggestions_count, %{count: length(assigns.results)})
    ]
    |> Enum.join(" ")
  end

  defp facet_state_announcement(assigns, :text), do: message(assigns, :results_count, %{count: length(assigns.results)})

  defp facet_label(%{label: nil, key: key}), do: to_string(key)
  defp facet_label(%{label: label}), do: label

  # Multi-select's selected-count reflects both additions and removals (a
  # chip removed is just the count going down) — one message key covers
  # both, rather than a bespoke "chip removed" sentence naming the chip,
  # since the chip's own label is no longer render state once it's gone.
  defp selection_announcement(%{multiple: true} = assigns),
    do: message(assigns, :selected_count, %{count: length(assigns.selected)})

  defp selection_announcement(%{multiple: false, selected: %Result{} = result, open: false} = assigns),
    do: message(assigns, :item_selected, %{label: result.label})

  defp selection_announcement(_assigns), do: ""

  # A slower response for an earlier keystroke could otherwise repopulate
  # `@results` after the query has since dropped below `min_chars`
  # (`cancel_async/2` in `apply_query/2` prevents that) — this is a pure
  # function of the current query/min_chars so the empty-state row below
  # never needs its own tracked assign.
  defp below_min_chars?(%{min_chars: min_chars, query: query}) do
    min_chars > 0 && String.length(String.trim(query)) < min_chars
  end

  # Whether multi-select has hit `max_selections` — further picking is
  # hidden from the listbox and communicated via a hint row rather than
  # rendering options that would just be rejected on click.
  defp at_max?(%{multiple: true, max_selections: max, selected: selected}) when not is_nil(max),
    do: length(selected) >= max

  defp at_max?(_assigns), do: false

  # Re-validates rather than trusting the caller boundary blindly — cheap,
  # and keeps this component safe to drive directly (as tests do) without
  # going through `Flicker.select/1`'s attr validation.
  defp chord_display(chord), do: chord |> Keyboard.validate!() |> Keyboard.display()

  defp chord_aria_keyshortcuts(chord), do: chord |> Keyboard.validate!() |> Keyboard.aria_keyshortcuts()

  # Flattens `results` into render rows, inserting a `{:header, label}` row
  # before the first result of each new contiguous `result.group` (Spec
  # 008). Every result's group is `nil` for a groupless provider, so this
  # always returns exactly `[{:option, result, index}, ...]` in that case —
  # bit-for-bit the rows the pre-Spec-008 markup rendered.
  defp rows_with_group_headers(results) do
    {rows, _last_group} =
      results
      |> Enum.with_index()
      |> Enum.flat_map_reduce(nil, fn {result, index}, last_group ->
        rows =
          if result.group && result.group != last_group do
            [{:header, result.group}, {:option, result, index}]
          else
            [{:option, result, index}]
          end

        {rows, result.group}
      end)

    rows
  end

  # Bulletproof visually-hidden CSS inlined directly on the element: Flicker
  # ships no stylesheet (ADR-002 keeps it framework-free), so a bare
  # `flicker-sr-only` class name would render visibly in every host app that
  # hasn't defined it themselves.
  @sr_only_style "position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; " <>
                   "overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0;"

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:input_id, input_id_for(assigns.id))
      |> assign(:listbox_id, listbox_id_for(assigns.id))
      |> assign(:below_min_chars, below_min_chars?(assigns))
      |> assign(:at_max, at_max?(assigns))
      |> assign(:rows, rows_with_group_headers(assigns.results))
      |> assign(:sr_only_style, @sr_only_style)
      |> assign(
        :aria_keyshortcuts,
        assigns.activate_with_keyboard && chord_aria_keyshortcuts(assigns.activate_with_keyboard)
      )
      |> assign(
        :kbd_hint_text,
        assigns.activate_with_keyboard && chord_display(assigns.activate_with_keyboard)
      )

    assigns = assign(assigns, :announcement, announcement(assigns))

    ~H"""
    <div
      id={@id}
      class={@theme.wrapper}
      phx-hook=".Nav"
      phx-target={@myself}
      phx-click-away="close"
      data-active-class={@theme.option_active}
      data-multiple={to_string(@multiple)}
      data-activate-with-keyboard={@activate_with_keyboard}
    >
      <div :if={@multiple} class={@theme.chip_list} role="list" aria-label={message(assigns, :selected_items)}>
        <span :for={result <- @selected} class={@theme.chip} role="listitem">
          <span>{result.label}</span>
          <button
            type="button"
            class={@theme.chip_remove}
            disabled={!@connected?}
            phx-click="remove_chip"
            phx-value-value={to_string(result.value)}
            phx-target={@myself}
            aria-label={message(assigns, :remove_chip, %{label: result.label})}
          >
            {message(assigns, :remove_icon)}
          </button>
        </span>
      </div>
      <label id={"#{@input_id}-label"} for={@input_id} class="flicker-sr-only" style={@sr_only_style}>
        {message(assigns, :search_placeholder)}
      </label>
      <input
        type="text"
        id={@input_id}
        name={"#{@id}-query"}
        role="combobox"
        aria-expanded={to_string(@open)}
        aria-controls={@listbox_id}
        aria-autocomplete="list"
        aria-haspopup="listbox"
        autocomplete="off"
        class={@theme.search_input}
        value={@query}
        placeholder={message(assigns, :search_placeholder)}
        disabled={!@connected?}
        aria-keyshortcuts={@aria_keyshortcuts}
        phx-keyup="query"
        phx-debounce={@debounce}
        phx-focus="focus"
        phx-target={@myself}
      />
      <kbd
        :if={@activate_with_keyboard}
        class={@theme.kbd_hint}
        aria-hidden="true"
        title={message(assigns, :keyboard_shortcut_hint, %{chord: @kbd_hint_text})}
        data-flicker-kbd-hint
      >
        {@kbd_hint_text}
      </kbd>
      <button
        :if={!@multiple && @selected}
        type="button"
        class={@theme.clear_button}
        disabled={!@connected?}
        phx-click="clear"
        phx-target={@myself}
        aria-label={message(assigns, :clear_selection)}
      >
        {message(assigns, :clear_selection)}
      </button>
      <button
        :if={@multiple && @selected != []}
        type="button"
        class={@theme.clear_button}
        disabled={!@connected?}
        phx-click="clear"
        phx-target={@myself}
        aria-label={message(assigns, :clear_all)}
      >
        {message(assigns, :clear_all)}
      </button>
      <div id={"#{@id}-announcer"} aria-live="polite" class="flicker-sr-only" style={@sr_only_style}>
        {@announcement}
      </div>
      <ul :if={@open} id={@listbox_id} role="listbox" aria-labelledby={"#{@input_id}-label"} class={@theme.listbox}>
        <li :if={@loading} class={@theme.loading_state}>{message(assigns, :loading)}</li>
        <li :if={@error} class={@theme.error_state}>{message(assigns, :error)}</li>
        <li :if={!@loading && !@error && @at_max} class={@theme.hint}>
          {message(assigns, :max_selections_reached, %{max: @max_selections})}
        </li>
        <li :if={!@loading && !@error && !@at_max && @below_min_chars} class={@theme.hint}>
          {message(assigns, :min_chars_hint, %{min_chars: @min_chars})}
        </li>
        <li :if={!@loading && !@error && !@at_max && !@below_min_chars && @results == []} class={@theme.empty_state}>
          {message(assigns, :no_results)}
        </li>
        <%= if !@at_max do %>
          <%= for row <- @rows do %>
            <%= case row do %>
              <% {:header, label} -> %>
                <li role="presentation" class={@theme.group_header}>{label}</li>
              <% {:option, result, index} -> %>
                <li id={option_id(assigns, index)} role="option" aria-selected="false" class={@theme.option}>
                  <button
                    type="button"
                    tabindex="-1"
                    phx-click="select"
                    phx-value-value={to_string(result.value)}
                    phx-target={@myself}
                    disabled={!@connected?}
                  >
                    <%= if @option != [] do %>
                      {render_slot(@option, result)}
                    <% else %>
                      <span>{result.label}</span> <span :if={result.sublabel}>{result.sublabel}</span>
                    <% end %>
                  </button>
                </li>
            <% end %>
          <% end %>
          <li :if={@has_more} class={@theme.hint}>{message(assigns, :keep_typing)}</li>
        <% end %>
      </ul>
      <%= if @field && @multiple do %>
        <input
          :for={result <- @selected}
          type="hidden"
          name={"#{@field.name}[]"}
          value={to_string(result.value)}
        />
        <%!--
          An empty `selected` needs its own sentinel: with no `[]` inputs at
          all, a raw form submit sends no param for this field, so the host
          can't tell "intentionally cleared" from "field never rendered" —
          the stored value would silently survive the submit. The blank-
          value `[]` input keeps the key present (`worker_ids => [""]`,
          filtered downstream) even though nothing is selected.
        --%>
        <input :if={@selected == []} type="hidden" name={"#{@field.name}[]"} value="" />
        <input :if={@selected == []} type="hidden" name={unused_marker_name(@field)} value="" />
      <% end %>
      <%= if @field && !@multiple do %>
        <input type="hidden" name={@field.name} id={@field.id} value={selected_value(@selected)} required={@required} />
        <input :if={blank?(selected_value(@selected))} type="hidden" name={unused_marker_name(@field)} value="" />
      <% end %>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Nav">
        // A generic focus-target listener (extraction notes #6): the
        // component `push_event`s "focusElementById" whenever DOM focus
        // needs to be moved explicitly (e.g. after opening or clearing,
        // since the element that had focus may be gone from the DOM).
        // Guarded so re-importing the module (multiple Nav instances on a
        // page) only attaches it once.
        if (!window.__flickerFocusListenerAttached) {
          window.__flickerFocusListenerAttached = true
          window.addEventListener("phx:focusElementById", e => {
            document.getElementById(e.detail.id)?.focus()
          })
        }

        // Keyboard activation (Spec 006). `activate_with_keyboard` is
        // already syntax-validated server-side (`Flicker.Keyboard`); the
        // "mod" alias is resolved here instead, because only the browser
        // knows whether it's running on macOS. One shared document
        // listener (not one per component) dispatches to whichever
        // registered chord matches — the registry is also how duplicate
        // chords across components are detected: first registration wins,
        // later ones just warn.
        function flickerIsMac() {
          const platform = navigator.userAgentData?.platform || navigator.platform || ""
          return /Mac|iPhone|iPad/.test(platform)
        }

        function flickerResolveModifier(modifier) {
          return modifier === "mod" ? (flickerIsMac() ? "meta" : "ctrl") : modifier
        }

        function flickerChordSignature(modifiers, key) {
          return `${Array.from(new Set(modifiers)).sort().join("+")}+${key.toLowerCase()}`
        }

        function flickerParseChordSignature(chord) {
          const parts = chord.split("+")
          const key = parts[parts.length - 1]
          const modifiers = parts.slice(0, -1).map(flickerResolveModifier)
          return flickerChordSignature(modifiers, key)
        }

        function flickerEventSignature(e) {
          const modifiers = []
          if (e.metaKey) modifiers.push("meta")
          if (e.ctrlKey) modifiers.push("ctrl")
          if (e.altKey) modifiers.push("alt")
          if (e.shiftKey) modifiers.push("shift")
          return flickerChordSignature(modifiers, e.key)
        }

        function flickerFormatChordForDisplay(chord) {
          const mac = flickerIsMac()
          const symbols = { meta: "⌘", ctrl: "Ctrl", alt: mac ? "⌥" : "Alt", shift: mac ? "⇧" : "Shift" }
          const parts = chord.split("+")
          const key = parts[parts.length - 1].toUpperCase()
          const modifiers = parts.slice(0, -1).map(flickerResolveModifier)
          const separator = mac ? "" : "+"
          return modifiers.map(m => symbols[m] || m).join(separator) + separator + key
        }

        if (!window.__flickerChordRegistry) window.__flickerChordRegistry = new Map()

        if (!window.__flickerActivationListenerAttached) {
          window.__flickerActivationListenerAttached = true
          document.addEventListener("keydown", e => {
            const hook = window.__flickerChordRegistry.get(flickerEventSignature(e))
            hook?.activateChord(e)
          })
        }

        export default {
          mounted() {
            this.activeIndex = -1
            // Set when ArrowDown opens a closed listbox (spec 001:
            // "ArrowDown also makes the first option active"; Alt+ArrowDown
            // opens without activating) — consumed the first time options
            // actually exist, since the "focus" round-trip re-renders the
            // loading state (no options yet) before the results land.
            this.pendingActivateFirst = false
            // Listen on the wrapper, not the input: the input node
            // re-renders as results change, which would strip a listener
            // bound to it directly, and keydown bubbles up from the
            // focused input to here anyway.
            this.onKeydown = e => this.handleKeydown(e)
            this.el.addEventListener("keydown", this.onKeydown)
            // No autofocus-on-mount here: an inline `Flicker.select/1` must
            // not steal page focus (or fire `phx-focus`, which would open
            // the listbox and run a search with no user interaction) just
            // because its LiveSocket connected. `Flicker.palette/1`'s
            // nested select is the one case that wants focus on mount, and
            // its own `.Palette` hook's `onOpen()` already focuses it
            // directly — this hook has no idea a palette exists.
            this.chordSignature = null
            const chord = this.el.dataset.activateWithKeyboard
            if (chord) this.registerChord(chord)
          },
          updated() {
            // The option set changed (the user typed, or results loaded) —
            // start fresh with no highlight (spec: active option resets to
            // none after results update), unless an ArrowDown-open is still
            // waiting for the first batch of options to activate.
            if (this.pendingActivateFirst) {
              const options = this.options()
              if (options.length > 0) {
                this.activeIndex = 0
                this.pendingActivateFirst = false
              } else {
                this.activeIndex = -1
              }
            } else {
              this.activeIndex = -1
            }
            this.render()
          },
          destroyed() {
            this.el.removeEventListener("keydown", this.onKeydown)
            // Only the winning registration ever owns the registry entry
            // (see registerChord) — a duplicate loser has nothing to undo.
            if (this.chordSignature && window.__flickerChordRegistry.get(this.chordSignature) === this) {
              window.__flickerChordRegistry.delete(this.chordSignature)
            }
          },
          registerChord(chord) {
            const signature = flickerParseChordSignature(chord)
            if (window.__flickerChordRegistry.has(signature)) {
              console.warn(
                `Flicker: activate_with_keyboard chord "${chord}" is already claimed by another ` +
                  "component on this page — the first registration wins, this one is inactive."
              )
              return
            }
            window.__flickerChordRegistry.set(signature, this)
            this.chordSignature = signature
            const hint = this.el.querySelector("[data-flicker-kbd-hint]")
            if (hint) hint.textContent = flickerFormatChordForDisplay(chord)
          },
          // Deliberately reuses the existing "focus"/"close" server events
          // (Spec 001) rather than adding new ones — activation is "press
          // the chord, then behave exactly like a click/focus would"
          // (Spec 006 design: no bespoke activation round-trip).
          activateChord(e) {
            const input = this.input()
            // `disabled` mirrors `@connected?` — inert until the socket
            // has joined (the dead-render rule, ADR-005), and there is no
            // stale activation to "queue": a keypress before then is
            // simply dropped.
            if (!input || input.disabled) return
            e.preventDefault()
            const isOpen = this.el.querySelector('[role="listbox"]') !== null
            if (document.activeElement === input && isOpen) {
              // Already focused and open — the chord toggles closed
              // (Spec 006 resolved open question: yes, toggle).
              input.blur()
              this.pushEventTo(this.el, "close", {})
            } else {
              input.focus()
            }
          },
          input() {
            return this.el.querySelector('input[type="text"]')
          },
          options() {
            return Array.from(this.el.querySelectorAll('[role="option"]'))
          },
          activeClass() {
            return this.el.dataset.activeClass
          },
          move(delta) {
            const options = this.options()
            if (options.length === 0) return
            // No wrap — stops at the last/first option (spec 001 deltas
            // from the origin, which wrapped via modulo).
            const next = this.activeIndex + delta
            this.activeIndex = Math.max(0, Math.min(options.length - 1, next))
            this.render()
          },
          handleKeydown(e) {
            const options = this.options()
            const isOpen = this.el.querySelector('[role="listbox"]') !== null
            switch (e.key) {
              case "ArrowDown":
                e.preventDefault()
                if (!isOpen) {
                  this.pendingActivateFirst = !e.altKey
                  this.pushEventTo(this.el, "focus", {})
                } else {
                  this.move(1)
                }
                break
              case "ArrowUp":
                if (isOpen) {
                  e.preventDefault()
                  this.move(-1)
                }
                break
              case "Enter":
                if (isOpen) {
                  // Never submit the surrounding form while the listbox is
                  // open — a classic combobox regression.
                  e.preventDefault()
                  if (this.activeIndex >= 0 && options[this.activeIndex]) {
                    options[this.activeIndex].querySelector("button")?.click()
                  }
                }
                break
              case "Escape":
                this.pushEventTo(this.el, "escape", {})
                break
              case "Tab":
                if (isOpen) this.pushEventTo(this.el, "close", {})
                break
              case "Backspace":
                // Multi-select only, and only when the input is empty —
                // otherwise Backspace edits the typed text as normal (spec
                // 002: "Backspace in an empty search input removes the last
                // chip").
                if (this.el.dataset.multiple === "true" && this.input()?.value === "") {
                  this.pushEventTo(this.el, "remove_last_chip", {})
                }
                break
              default:
                break
            }
          },
          render() {
            const input = this.input()
            const activeClass = this.activeClass()
            this.options().forEach((option, i) => {
              const active = i === this.activeIndex
              option.setAttribute("aria-selected", active ? "true" : "false")
              const button = option.querySelector("button")
              if (button && activeClass) button.classList.toggle(activeClass, active)
              if (active) {
                input?.setAttribute("aria-activedescendant", option.id)
                option.scrollIntoView({ block: "nearest" })
              }
            })
            if (this.activeIndex < 0) input?.removeAttribute("aria-activedescendant")
          }
        }
      </script>
    </div>
    """
  end
end
