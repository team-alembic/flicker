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
  completed `status:active` doesn't leak into the `ilike` match). The
  parsed facet filter also ANDs into the provider's own record query (not
  just the autocomplete UX) — see `run_faceted_search/2`'s `:text` clause.

  The `.Nav` colocated hook reports the input's real `selectionStart` on
  every keyup/click/select (Spec 003's cursor-tracking follow-up, now
  closed) — the `cursor` assign carries it (`nil` before the hook's first
  event, or after this component sets the query text itself, falling back
  to end-of-text per `Flicker.FacetSuggest.classify/3`), so a cursor moved
  back into an already-typed facet token classifies right there, not "at
  the end".

  `paginate` ([Spec 010](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-010-windowed-search.md),
  default `false`) switches the "keep typing to narrow" `limit + 1` probe
  into windowed infinite scroll: reaching the tail of the listbox (via the
  `.Nav` hook's `IntersectionObserver` sentinel, or `ArrowDown` on the last
  option) fetches the next `limit`-sized window (`offset: window * limit`)
  and appends it to `results` instead of replacing them. A new query, or a
  facet-context change, resets `window` to `0`, discards any in-flight
  window fetch, and scrolls the listbox back to the top — windowing only
  ever accumulates for the *current* query. Capped by `max_windows`
  (default 10): past the cap — or as soon as core detects a provider
  ignoring `:offset` (a window identical to the one before it) — the list
  is marked complete and the tail renders the same "keep typing to narrow"
  hint windowing otherwise replaces, rather than a bespoke dead-end state.
  `paginate: false` (the default) is byte-identical to pre-Spec-010
  behaviour — none of this machinery engages.
  """

  use Phoenix.LiveComponent

  alias Flicker.{CursorContext, FacetSuggest, Keyboard, Messages, Provider, Query, Result}

  require Logger

  @default_limit 25
  @default_min_chars 0
  @default_max_windows 10

  @impl true
  def update(assigns, socket) do
    prev_actor = socket.assigns[:actor]
    prev_tenant = socket.assigns[:tenant]

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
      |> assign_new(:cursor, fn -> nil end)
      |> assign_new(:navigate_on_select, fn -> false end)
      |> assign_new(:paginate, fn -> false end)
      |> assign_new(:max_windows, fn -> @default_max_windows end)
      |> assign_new(:windows_loaded, fn -> 0 end)
      |> assign_new(:loading_more, fn -> false end)
      |> assign_new(:window_complete, fn -> false end)
      |> assign_new(:window_head, fn -> nil end)
      |> assign_new(:last_appended_count, fn -> nil end)
      |> assign_new(:current_query, fn -> nil end)
      |> assign_new(:selected_slot, fn -> [] end)
      |> assign_new(:max_visible, fn -> nil end)

    socket =
      socket
      |> assign_new(:selected, fn -> if socket.assigns.multiple, do: [] end)
      |> assign_new(:limit, fn -> @default_limit end)
      |> assign_new(:min_chars, fn -> @default_min_chars end)
      |> assign(:connected?, Phoenix.LiveView.connected?(socket))
      |> resolve_selected()
      |> research_on_scope_change(prev_actor, prev_tenant)

    {:ok, socket}
  end

  # The host swapping `actor` (or `tenant`) mid-search — e.g. the
  # playground's "acting as" toggle — must re-run the current query against
  # the new scope, otherwise the results sit stale (the actor change looked
  # like it did nothing). Fires whenever there's an active query or an open
  # listbox: re-running re-opens the listbox so the effect of switching who's
  # searching is immediately visible, which is the whole point of exposing a
  # live `actor`. An untouched picker (blank query, closed) is left alone —
  # it has nothing to re-run and shouldn't pop open on an unrelated render.
  defp research_on_scope_change(%{assigns: %{connected?: true}} = socket, prev_actor, prev_tenant) do
    scope_changed? =
      socket.assigns[:actor] != prev_actor or socket.assigns[:tenant] != prev_tenant

    active? = socket.assigns.open or socket.assigns.query != ""

    if scope_changed? and active? do
      apply_query(socket, socket.assigns.query, socket.assigns.cursor)
    else
      socket
    end
  end

  defp research_on_scope_change(socket, _prev_actor, _prev_tenant), do: socket

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

    {:noreply, focus_input(socket)}
  end

  # `phx-keyup` fires for *every* key, including the Enter/Escape/Tab
  # keydowns the `.Nav` hook has already turned into a select/close — and
  # that trailing keyup races the resulting server round trip, smuggling a
  # stale `value`/`cursor` into a "query" event that reopens the listbox
  # (or clears a just-made selection) a debounce later. None of these keys
  # can have edited the text, so their keyups are ignored outright (caught
  # by Spec 007's browser-driven suite; PhoenixTest couldn't see it because
  # it never fires the trailing keyup a real browser does).
  def handle_event("query", %{"key" => key}, socket) when key in ["Enter", "Escape", "Tab"], do: {:noreply, socket}

  def handle_event("query", %{"value" => text} = params, socket) do
    cursor = CursorContext.parse_selection_start(params["cursor"])

    cond do
      text == socket.assigns.query and cursor == socket.assigns.cursor ->
        {:noreply, socket}

      # The caret moved but the text didn't (arrow/Home/End keyups). With
      # no facets configured there is no cursor-dependent context to
      # reclassify — mirrors the "cursor" event's `facets: []` no-op below
      # — so re-running the same search would only churn the DOM, resetting
      # the client-side option highlight the arrow key just moved (Spec
      # 007's browser suite caught Enter-after-ArrowDown no-oping because
      # of exactly this).
      text == socket.assigns.query and socket.assigns.facets == [] ->
        {:noreply, assign(socket, :cursor, cursor)}

      true ->
        {:noreply, socket |> clear_stale_selection(text) |> apply_query(text, cursor)}
    end
  end

  # A cursor moving without the query text changing (a click, or a
  # keyboard/mouse selection change with no typing) — no facets configured
  # means there's no context to reclassify, so this is a no-op rather than
  # redoing the same record search for nothing.
  def handle_event("cursor", _params, %{assigns: %{facets: []}} = socket), do: {:noreply, socket}

  def handle_event("cursor", %{"cursor" => cursor}, socket) do
    socket = assign(socket, :cursor, CursorContext.parse_selection_start(cursor))
    {:noreply, run_search(socket, String.trim(socket.assigns.query))}
  end

  # Reads `phx-value-result`, deliberately not `phx-value-value`: LiveView's
  # client-side `extractMeta` unconditionally overwrites `meta.value` with
  # `el.value` for any element where that's defined (`view.ts`), and a
  # `<button>` always has a native `.value` DOM property (`""` unless a
  # `value=` HTML attribute is set) — clobbering a `phx-value-value` custom
  # param with an empty string on *every* option click, in every browser
  # (caught by Spec 007's browser suite; `Phoenix.LiveViewTest`'s
  # Floki-based click simulation has no DOM `.value` property to clobber
  # with, so no ExUnit/PhoenixTest test could ever have seen this).
  def handle_event("select", %{"result" => raw_value}, socket) do
    result = Enum.find(socket.assigns.results, &(to_string(&1.value) == raw_value))
    select_result(result, raw_value, socket)
  end

  def handle_event("remove_chip", %{"result" => raw_value}, %{assigns: %{multiple: true}} = socket) do
    new_selected = Enum.reject(socket.assigns.selected, &(to_string(&1.value) == raw_value))

    socket =
      socket
      |> assign(selected: new_selected)
      |> notify_multi_selection(new_selected)

    {:noreply, focus_input(socket)}
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
      |> assign(selected: [], query: "", cursor: nil, open: false)
      |> notify_multi_selection([])

    {:noreply, focus_input(socket, "")}
  end

  def handle_event("clear", _params, socket) do
    socket =
      socket
      |> assign(selected: nil, query: "", cursor: nil, open: false)
      |> notify_selection(nil)

    {:noreply, focus_input(socket, "")}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, open: false)}
  end

  def handle_event("escape", _params, socket) do
    cond do
      socket.assigns.open ->
        {:noreply, assign(socket, open: false)}

      socket.assigns.query != "" ->
        {:noreply, socket |> assign(query: "", cursor: nil) |> run_search("")}

      true ->
        {:noreply, socket}
    end
  end

  # A `load-more` window (Spec 010) — the `.Nav` hook's `IntersectionObserver`
  # sentinel, or `ArrowDown` on the last option, pushes this. Debounced to
  # one in-flight window at a time: ignored while a window is already
  # loading, the list is already complete, or no initial window has loaded
  # yet (`windows_loaded == 0` — e.g. still below `min_chars`, or a facet
  # suggestion, not a record search, is currently driving the listbox).
  @impl true
  def handle_event(
        "load-more",
        _params,
        %{assigns: %{paginate: true, loading_more: false, window_complete: false, windows_loaded: loaded}} = socket
      )
      when loaded > 0 do
    {:noreply, run_next_window(socket)}
  end

  def handle_event("load-more", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:search, {:ok, {:record, {:ok, results}}}, socket) do
    limit = socket.assigns.limit
    available = filter_available(results, socket)
    window_results = Enum.take(available, limit)
    has_more = length(available) > limit

    {:noreply,
     assign(socket,
       results: window_results,
       has_more: has_more,
       loading: false,
       error: false,
       windows_loaded: 1,
       loading_more: false,
       window_head: window_head(window_results),
       window_complete: window_complete?(has_more, 1, socket.assigns.max_windows),
       last_appended_count: nil
     )}
  end

  def handle_async(:search, {:ok, {:record, {:error, reason}}}, socket) do
    Logger.warning("Flicker search failed: #{inspect(reason)}")

    {:noreply,
     assign(socket,
       results: [],
       has_more: false,
       loading: false,
       error: true,
       loading_more: false,
       window_complete: true,
       last_appended_count: nil
     )}
  end

  def handle_async(:search, {:ok, {:facet, {:ok, results}}}, socket) do
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

  def handle_async(:search, {:ok, {:facet, {:error, reason}}}, socket) do
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

    {:noreply,
     assign(socket,
       results: [],
       has_more: false,
       loading: false,
       error: true,
       loading_more: false
     )}
  end

  # Window N+1 landing (Spec 010) — appended, never replacing, `results`.
  # `target` is the window index this response fills; it's only ever
  # `socket.assigns.windows_loaded + 1` (the debounce guard on `load-more`
  # never lets a second window request start while one is in flight), so
  # there is no separate staleness check to make here beyond the
  # `start_async/3` same-name cancellation `reset_window/1` already invokes
  # on a fresh query.
  @impl true
  def handle_async(:load_more, {:ok, {target, {:ok, results}}}, socket) do
    {:noreply, append_window(socket, target, results)}
  end

  def handle_async(:load_more, {:ok, {_target, {:error, reason}}}, socket) do
    Logger.warning("Flicker load-more failed: #{inspect(reason)}")
    {:noreply, assign(socket, loading_more: false, window_complete: true)}
  end

  def handle_async(:load_more, {:exit, {:shutdown, :cancel}}, socket), do: {:noreply, socket}

  def handle_async(:load_more, {:exit, reason}, socket) do
    Logger.warning("Flicker load-more task exited: #{inspect(reason)}")
    {:noreply, assign(socket, loading_more: false, window_complete: true)}
  end

  defp suggestion?(%Result{meta: %{flicker_facet: true}}), do: true
  defp suggestion?(_result), do: false

  defp select_result(%Result{meta: %{flicker_facet: true, insert: insert}}, _raw_value, socket) do
    new_text =
      FacetSuggest.replace_current_token(socket.assigns.query, insert, socket.assigns.cursor)

    # `apply_query/3`'s default `cursor: nil` is deliberate here, not an
    # oversight: the browser resets the caret to the end of the input's
    # value once `focus_input/2` sets it, so the server's notion of "where
    # the caret is" should fall back to end-of-text too, matching what the
    # DOM will actually do.
    {:noreply, focus_input(apply_query(socket, new_text), new_text)}
  end

  defp select_result(result, _raw_value, %{assigns: %{multiple: true}} = socket) do
    if result && addable?(socket) do
      new_selected = socket.assigns.selected ++ [result]

      # Clear the search text after adding a chip so the next pick starts from
      # a fresh, full list rather than the previous term — `filter_selected/2`
      # keeps the just-added record out of the shown results in the meantime,
      # then the re-run empty search drops the typed filter entirely.
      socket =
        socket
        |> assign(selected: new_selected)
        |> update_results(&filter_selected(&1, new_selected))
        |> notify_multi_selection(new_selected)
        |> apply_query("")

      {:noreply, focus_input(socket, "")}
    else
      {:noreply, focus_input(socket)}
    end
  end

  # `result` is nil when the clicked value no longer matches anything in
  # `@results` (async results landed, or the facet context flipped, between
  # render and click) — a no-op rather than clearing whatever was already
  # selected, mirroring the `multiple: true` clause's `if result && ...`
  # guard above.
  defp select_result(nil, _raw_value, socket), do: {:noreply, socket}

  defp select_result(result, _raw_value, socket) do
    text = display_text(result)

    socket =
      socket
      |> assign(selected: result, query: text, open: false)
      |> notify_selection(result)
      |> maybe_navigate(result)
      |> focus_input(text)

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

  defp apply_query(socket, text, cursor \\ nil) do
    trimmed = String.trim(text)
    socket = socket |> reset_window() |> assign(query: text, cursor: cursor, open: true)

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
  defp run_search(%{assigns: %{facets: []}} = socket, text), do: run_record_search(socket, %Query{text: text})

  # Classifies off `socket.assigns.query` (the raw, untyped-through text
  # `apply_query/3` just assigned) rather than the `text` argument here —
  # the latter is trimmed for the plain-record-search path and trimming
  # would erase the trailing-space transition out of facet-value position
  # (`"status:active "` classifying as `:text`, not still `{:value, ...}`).
  # `socket.assigns.cursor` is the real caret position the `.Nav` hook last
  # reported (`nil` — end-of-text — before its first event, or right after
  # this component sets the query text itself).
  defp run_search(socket, _trimmed_text) do
    context =
      FacetSuggest.classify(socket.assigns.query, socket.assigns.facets, socket.assigns.cursor)

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

  # Facet-value position for a facet with a closed picklist (`:enum` or
  # `:boolean`, Spec 003's type table) — synchronous, no provider round-trip.
  defp run_faceted_search(socket, {:value, %{type: type} = facet, prefix}) when type in [:enum, :boolean] do
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
        {:facet,
         FacetSuggest.related_search(facet, prefix,
           actor: actor,
           tenant: tenant,
           limit: fetch_limit
         )}
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

  # Free-text position: an ordinary record search against the full parsed
  # query — free text hits the provider's own text match (a completed
  # `status:active` token never leaks into the `ilike` match) *and* the
  # parsed facet tokens are passed through so the provider can scope which
  # records are offered before the text match runs (guides/faceted-search.md);
  # `Flicker.Providers.AshResource.search/2` composes `Flicker.Query.to_filter/2`
  # into its Ash query for this, `Flicker.Providers.Static` ignores `.facets`
  # (documented on each provider).
  defp run_faceted_search(socket, :text) do
    parsed_query = Query.parse(text_for_facet_parse(socket), socket.assigns.facets)
    run_record_search(socket, parsed_query)
  end

  defp text_for_facet_parse(socket), do: socket.assigns.query

  defp run_record_search(socket, query) do
    provider = socket.assigns.provider
    actor = socket.assigns[:actor]
    tenant = socket.assigns[:tenant]
    # Fetch one more than we display: `has_more` without a count query
    # (extraction notes #3) — "keep typing to narrow" instead of paginating,
    # unless `paginate` (Spec 010) turns the probe into window 0 of many.
    fetch_limit = socket.assigns.limit + 1
    opts = search_opts(socket, actor, tenant, fetch_limit, 0)

    socket
    |> assign(loading: true, error: false, current_query: query)
    |> start_async(:search, fn -> {:record, Provider.run_search(provider, query, opts)} end)
  end

  # `:offset` is only ever sent when `paginate` is on — omitting the key
  # entirely (rather than sending `offset: 0`) is what keeps `paginate:
  # false`'s provider calls byte-identical to pre-Spec-010 behaviour (the
  # regression the acceptance criteria call for).
  defp search_opts(%{assigns: %{paginate: true}}, actor, tenant, limit, offset),
    do: [actor: actor, tenant: tenant, limit: limit, offset: offset]

  defp search_opts(_socket, actor, tenant, limit, _offset), do: [actor: actor, tenant: tenant, limit: limit]

  # Requests the next window (Spec 010) — `handle_event("load-more", ...)`'s
  # debounce guard already ensures at most one of these runs at a time, and
  # that `current_query`/`windows_loaded` reflect the query currently on
  # screen (a fresh query resets both via `reset_window/1`).
  defp run_next_window(socket) do
    provider = socket.assigns.provider
    actor = socket.assigns[:actor]
    tenant = socket.assigns[:tenant]
    limit = socket.assigns.limit
    target = socket.assigns.windows_loaded + 1
    offset = socket.assigns.windows_loaded * limit
    query = socket.assigns.current_query
    opts = search_opts(socket, actor, tenant, limit + 1, offset)

    socket
    |> assign(loading_more: true, error: false)
    |> start_async(:load_more, fn -> {target, Provider.run_search(provider, query, opts)} end)
  end

  # Appends window `target`'s results, unless core detects the provider
  # ignored `:offset` (this window's first result identical to the
  # previous window's) — the no-progress behavioural probe (Spec 010): a
  # provider that always returns the same first window gets exactly this
  # one extra request, then the list is marked complete instead of
  # requesting forever.
  defp append_window(socket, target, results) do
    limit = socket.assigns.limit
    available = filter_available(results, socket)
    window_results = Enum.take(available, limit)
    has_more = length(available) > limit

    if stalled?(socket, window_results) do
      assign(socket, loading_more: false, window_complete: true, last_appended_count: nil)
    else
      assign(socket,
        results: socket.assigns.results ++ window_results,
        has_more: has_more,
        loading_more: false,
        windows_loaded: target,
        window_head: window_head(window_results),
        window_complete: window_complete?(has_more, target, socket.assigns.max_windows),
        last_appended_count: length(window_results)
      )
    end
  end

  defp stalled?(_socket, []), do: false
  defp stalled?(%{assigns: %{window_head: nil}}, _window_results), do: false

  defp stalled?(%{assigns: %{window_head: head}}, window_results), do: window_head(window_results) == head

  defp window_head([]), do: nil
  defp window_head([%Result{value: value} | _]), do: to_string(value)

  defp window_complete?(has_more, windows_loaded, max_windows), do: !has_more || windows_loaded >= max_windows

  # Windowing (Spec 010) is only ever active for an ordinary free-text
  # record search — facet-key/value suggestions (Spec 003) are never
  # paginated, so `paginate: true` configured alongside `facets` still
  # renders exactly the facet-suggestion UI while the cursor is in facet
  # position.
  defp paginating?(%{paginate: true, facet_context: :text}), do: true
  defp paginating?(_assigns), do: false

  # A new query (or facet-context change) always restarts windowing at 0
  # (Spec 010) — any in-flight `load-more` window belongs to the query
  # being replaced, so it's cancelled here rather than left to land and
  # append onto results it no longer matches. `cancel_async/2` is a no-op
  # when no `:load_more` task is running (nothing to cancel most of the
  # time).
  defp reset_window(socket) do
    socket
    |> cancel_async(:load_more)
    |> assign(
      windows_loaded: 0,
      loading_more: false,
      window_complete: false,
      window_head: nil,
      last_appended_count: nil
    )
    |> maybe_scroll_listbox_top()
  end

  defp maybe_scroll_listbox_top(%{assigns: %{paginate: true}} = socket),
    do: push_event(socket, "scrollListboxToTop", %{id: listbox_id_for(socket.assigns.id)})

  defp maybe_scroll_listbox_top(socket), do: socket

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

  # Phoenix.LiveView's DOM patching deliberately never touches a focused
  # text input's `value` (`DOM.mergeFocusedInput` in `dom.ts` excludes it
  # unconditionally, focused or not dirty) — the standard guard against a
  # server round trip clobbering what the user is mid-typing. But every
  # caller here is re-pointing `@query` to something the user did *not*
  # just type (a selection's label, a cleared/inserted facet token), while
  # the input typically keeps DOM focus throughout (no blur happens), so
  # that guard silently leaves the visible input showing stale or blank
  # text even though the server-side `query` assign (and the hidden field)
  # are correct (caught by Spec 007's browser suite: `ExUnit`/`PhoenixTest`
  # simulate clicks and events directly against assigns, never actually
  # replaying LiveView's client-side "skip the focused input" DOM patch
  # logic). `focus_input/2` force-sets the value via a `push_event`
  # (`phx:focusElementById`, handled in the `.Nav` hook below) instead of
  # relying on the render diff.
  defp focus_input(socket, value \\ nil)

  defp focus_input(socket, nil), do: push_event(socket, "focusElementById", %{id: input_id(socket)})

  defp focus_input(socket, value), do: push_event(socket, "focusElementById", %{id: input_id(socket), value: value})

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

  defp state_announcement(%{open: true} = assigns), do: text_state_announcement(assigns)

  defp state_announcement(_assigns), do: ""

  # A `paginate`-d window that just appended (Spec 010) gets its own
  # message-keyed announcement ("N more results, M total") instead of the
  # plain results count — `last_appended_count` is `reset_window/1`'s
  # own reset field, so it's only ever non-nil right after a successful
  # append of the *current* query's results, never a stale prior query's.
  defp text_state_announcement(%{paginate: true, last_appended_count: count} = assigns) when is_integer(count),
    do: message(assigns, :more_results_appended, %{count: count, total: length(assigns.results)})

  defp text_state_announcement(assigns), do: message(assigns, :results_count, %{count: length(assigns.results)})

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

  defp facet_state_announcement(assigns, :text), do: text_state_announcement(assigns)

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
  # `max_visible` (Spec 013) caps how many selected items the `:selected` slot
  # renders before the rest collapse into a "+N" token; `nil` shows them all.
  defp visible_selected(selected, nil), do: selected
  defp visible_selected(selected, max_visible), do: Enum.take(selected, max_visible)

  defp overflow_count(_selected, nil), do: 0
  defp overflow_count(selected, max_visible), do: max(length(selected) - max_visible, 0)

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

  # The load-more sentinel must stay *in flow* at the tail of the listbox —
  # `@sr_only_style`'s `position: absolute` would position it relative to
  # the wrapper (outside the scrolling `<ul>`), so the `IntersectionObserver`
  # rooted on the listbox would either never see it enter the scrollport or
  # see it permanently, and scroll-to-tail windowing (Spec 010) silently
  # breaks in a real browser (caught by Spec 007's browser-driven suite).
  # `aria-hidden` on the row keeps it out of the accessibility tree; 1px of
  # bare height keeps it visually invisible without breaking geometry.
  @sentinel_style "height: 1px; padding: 0; margin: 0; border: 0; list-style: none;"

  # The combobox `<input>` (and its visually-hidden label), rendered once and
  # reused by both the single- and multiple-select layouts — only the class
  # differs (`:search_input` vs the borderless `:multi_input`), passed in as
  # `:input_class`, so the shared ARIA/`phx-*` wiring can't drift between the
  # two. Called as `{combobox_input(assign(assigns, :input_class, ...))}`.
  defp combobox_input(assigns) do
    ~H"""
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
      class={@input_class}
      value={@query}
      placeholder={message(assigns, :search_placeholder)}
      disabled={!@connected?}
      aria-keyshortcuts={@aria_keyshortcuts}
      phx-keyup="query"
      phx-debounce={@debounce}
      phx-focus="focus"
      phx-target={@myself}
    />
    """
  end

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
      |> assign(:sentinel_style, @sentinel_style)
      |> assign(
        :aria_keyshortcuts,
        assigns.activate_with_keyboard && chord_aria_keyshortcuts(assigns.activate_with_keyboard)
      )
      |> assign(
        :kbd_hint_text,
        assigns.activate_with_keyboard && chord_display(assigns.activate_with_keyboard)
      )

    paginating = paginating?(assigns)

    assigns =
      assigns
      |> assign(:paginating, paginating)
      |> assign(:show_loading_more, paginating && assigns.loading_more)
      |> assign(
        :show_sentinel,
        paginating && assigns.has_more && !assigns.window_complete && !assigns.loading_more
      )
      |> assign(:show_narrow_hint, assigns.has_more && (!paginating || assigns.window_complete))
      |> assign(:aria_busy, if(assigns.paginate, do: to_string(assigns.loading_more)))

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
      data-paginate={if @paginate, do: "true"}
    >
      <%!--
        Multiple: chips and the text input share one bordered field box
        (`:multi_field`) so selected values sit *inside* the input, with the
        borderless input growing to fill and "clear all" vertically centred
        in the box. Single: the plain bordered input with an overlaid clear
        button, unchanged.
      --%>
      <div :if={@multiple} class={@theme.multi_field}>
        <%!--
          A `:selected` slot (Spec 013) renders each selected item's own
          visual (e.g. an avatar), laid out in `:selected_stack` with a "+N"
          overflow past `max_visible` — otherwise the default text chips.
          Either way the library owns the remove control so removal can target
          this component.
        --%>
        <div
          :if={@selected_slot != []}
          class={@theme.selected_stack}
          role="list"
          aria-label={message(assigns, :selected_items)}
        >
          <span :for={result <- visible_selected(@selected, @max_visible)} class={@theme.selected_item} role="listitem">
            {render_slot(@selected_slot, result)}
            <button
              type="button"
              class={@theme.chip_remove}
              disabled={!@connected?}
              phx-click="remove_chip"
              phx-value-result={to_string(result.value)}
              phx-target={@myself}
              aria-label={message(assigns, :remove_chip, %{label: result.label})}
            >
              {message(assigns, :remove_icon)}
            </button>
          </span>
          <span
            :if={overflow_count(@selected, @max_visible) > 0}
            class={@theme.selected_overflow}
            aria-label={message(assigns, :selected_overflow, %{count: overflow_count(@selected, @max_visible)})}
          >
            +{overflow_count(@selected, @max_visible)}
          </span>
        </div>
        <div
          :if={@selected_slot == []}
          class={@theme.chip_list}
          role="list"
          aria-label={message(assigns, :selected_items)}
        >
          <span :for={result <- @selected} class={@theme.chip} role="listitem">
            <span>{result.label}</span>
            <button
              type="button"
              class={@theme.chip_remove}
              disabled={!@connected?}
              phx-click="remove_chip"
              phx-value-result={to_string(result.value)}
              phx-target={@myself}
              aria-label={message(assigns, :remove_chip, %{label: result.label})}
            >
              {message(assigns, :remove_icon)}
            </button>
          </span>
        </div>
        {combobox_input(assign(assigns, :input_class, @theme.multi_input))}
        <button
          :if={@selected != []}
          type="button"
          class={@theme.multi_clear}
          disabled={!@connected?}
          phx-click="clear"
          phx-target={@myself}
          aria-label={message(assigns, :clear_all)}
        >
          {message(assigns, :clear_all)}
        </button>
      </div>

      <%= unless @multiple do %>
        {combobox_input(assign(assigns, :input_class, @theme.search_input))}
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
          :if={@selected}
          type="button"
          class={@theme.clear_button}
          disabled={!@connected?}
          phx-click="clear"
          phx-target={@myself}
          aria-label={message(assigns, :clear_selection)}
        >
          {message(assigns, :clear_selection)}
        </button>
      <% end %>
      <div id={"#{@id}-announcer"} aria-live="polite" class="flicker-sr-only" style={@sr_only_style}>
        {@announcement}
      </div>
      <ul
        :if={@open}
        id={@listbox_id}
        role="listbox"
        aria-labelledby={"#{@input_id}-label"}
        aria-busy={@aria_busy}
        class={@theme.listbox}
      >
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
                <li
                  id={option_id(assigns, index)}
                  role="option"
                  aria-selected="false"
                >
                  <%!--
                    The themed `:option`/`:suggestion` class (padding, hover,
                    and the JS-toggled active highlight) lives on the button,
                    not the wrapping `<li>`, so the whole padded row is one
                    click target — an unstyled inline button sized to just its
                    text left the row's padding dead to clicks, and the active
                    highlight covered only the text (caught by hand: clicking
                    an active row did nothing unless you hit the label itself).
                  --%>
                  <button
                    type="button"
                    tabindex="-1"
                    class={if suggestion?(result), do: @theme.suggestion, else: @theme.option}
                    style="display:block;width:100%;text-align:left"
                    phx-click="select"
                    phx-value-result={to_string(result.value)}
                    phx-target={@myself}
                    disabled={!@connected?}
                  >
                    <%= cond do %>
                      <% @option != [] -> %>
                        {render_slot(@option, result)}
                      <% suggestion?(result) -> %>
                        <span class={@theme.suggestion_token}>{result.label}</span>
                        <span :if={result.sublabel} class={@theme.option_sublabel}>{result.sublabel}</span>
                      <% true -> %>
                        <span class={@theme.option_label}>{result.label}</span>
                        <span :if={result.sublabel} class={@theme.option_sublabel}>{result.sublabel}</span>
                    <% end %>
                  </button>
                </li>
            <% end %>
          <% end %>
          <li :if={@show_loading_more} class={@theme.loading_more} aria-hidden="true">
            {message(assigns, :loading_more)}
          </li>
          <li :if={@show_sentinel} data-flicker-sentinel aria-hidden="true" style={@sentinel_style}></li>
          <li :if={@show_narrow_hint} class={@theme.hint}>{message(assigns, :keep_typing)}</li>
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
        // since the element that had focus may be gone from the DOM), and
        // optionally a `value` to force onto the input. LiveView's own DOM
        // patching deliberately skips a focused input's `value` on every
        // diff (`DOM.mergeFocusedInput` in `dom.ts`, unconditionally,
        // regardless of whether the client's text is actually "dirty") —
        // so a selection/clear/facet-insert that reassigns `@query` while
        // the input keeps DOM focus throughout never reaches the browser
        // through the ordinary render diff; setting `.value` here,
        // directly, is what actually gets it there (caught by Spec 007's
        // browser suite — `ExUnit`/`PhoenixTest` never replay LiveView's
        // client-side DOM patching, so no prior test saw the input stay
        // stale/blank after a real selection). Guarded so re-importing the
        // module (multiple Nav instances on a page) only attaches it once
        // — and shared with `Flicker.Components.Search`'s own copy of this
        // exact block (see its comment): `Flicker.search/1` and
        // `Flicker.select/1` can both be mounted on the same page (Spec
        // 005's dev playground layout), and only the first hook to mount
        // would otherwise win this registration, silently leaving the
        // other's `push_event`s handled by a stale/mismatched listener.
        if (!window.__flickerFocusListenerAttached) {
          window.__flickerFocusListenerAttached = true
          window.addEventListener("phx:focusElementById", e => {
            const el = document.getElementById(e.detail.id)
            if (!el) return
            if (e.detail.value !== undefined) el.value = e.detail.value
            el.focus()
          })
        }

        // Windowed search (Spec 010): a fresh query resets `window` to 0
        // server-side and pushes this event so the listbox scrolls back to
        // the top — otherwise the user would be left scrolled deep into
        // results that just got replaced out from under them.
        if (!window.__flickerScrollTopListenerAttached) {
          window.__flickerScrollTopListenerAttached = true
          window.addEventListener("phx:scrollListboxToTop", e => {
            const listbox = document.getElementById(e.detail.id)
            if (listbox) listbox.scrollTop = 0
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
          // Case-insensitive: Chromium's `userAgentData.platform` reports
          // "macOS" (lowercase `m`), which a case-sensitive `/Mac/` test
          // never matches — so `mod+k` silently resolved to `ctrl` instead
          // of `meta` on every Mac running Chrome/Edge (Cmd+K did nothing,
          // Ctrl+K worked). `navigator.platform` ("MacIntel") happened to
          // match the old regex, so Safari/Firefox masked the bug.
          const platform = navigator.userAgentData?.platform || navigator.platform || ""
          return /mac|iphone|ipad/i.test(platform)
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
            this.optionsSignature = this.options().map(o => o.id).join("|")
            // Set when ArrowDown opens a closed listbox (spec 001:
            // "ArrowDown also makes the first option active"; Alt+ArrowDown
            // opens without activating) — consumed the first time options
            // actually exist, since the "focus" round-trip re-renders the
            // loading state (no options yet) before the results land.
            this.pendingActivateFirst = false
            // Set when a `load-more` window was requested (Spec 010) —
            // unlike an ordinary results update, the highlight must
            // *continue* into the newly-appended window rather than
            // resetting, so the keyboard user who pressed ArrowDown at the
            // end sees it keep moving once the window lands.
            this.pendingLoadMore = false
            this.sentinelObserver = null
            // Listen on the wrapper, not the input: the input node
            // re-renders as results change, which would strip a listener
            // bound to it directly, and keydown bubbles up from the
            // focused input to here anyway.
            this.onKeydown = e => this.handleKeydown(e)
            this.el.addEventListener("keydown", this.onKeydown)
            // Keep the input focused when an option is clicked with the
            // mouse: without this, `mousedown` shifts focus to the clicked
            // option `<button>`, blurring the input; `select_result/3` then
            // programmatically refocuses it, and that refocus fires
            // `phx-focus`, reopening the listbox the instant after the
            // selection closed it (the dropdown "flickers back up" on click-
            // select, never on keyboard-select — which keeps input focus).
            // Preventing the mousedown default keeps focus on the input, so
            // the click still selects but no blur/refocus round trip happens.
            this.onOptionMouseDown = e => {
              if (e.target.closest('[role="option"]')) e.preventDefault()
            }
            this.el.addEventListener("mousedown", this.onOptionMouseDown)
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
            this.setupSentinelObserver()
            this.attachCursorReporting()
          },
          updated() {
            // The option set changed (the user typed, or results loaded) —
            // start fresh with no highlight (spec: active option resets to
            // none after results update), unless an ArrowDown-open is still
            // waiting for the first batch of options to activate, or a
            // `load-more` window is landing (Spec 010, see `pendingLoadMore`
            // above).
            const options = this.options()
            const signature = options.map(o => o.id).join("|")
            if (this.pendingActivateFirst) {
              if (options.length > 0) {
                this.activeIndex = 0
                this.pendingActivateFirst = false
              } else {
                this.activeIndex = -1
              }
            } else if (this.pendingLoadMore) {
              this.pendingLoadMore = false
              this.activeIndex = Math.min(this.activeIndex, options.length - 1)
            } else if (signature === this.optionsSignature) {
              // Same option set — this re-render wasn't caused by results
              // changing (a cursor sync, an unrelated parent assign, an
              // identical re-search). Keep the highlight where the arrow keys
              // left it instead of snapping back to none, which read as the
              // down-arrow "catching" and jumping to the top of the list.
              this.activeIndex = Math.min(this.activeIndex, options.length - 1)
            } else {
              this.activeIndex = -1
            }
            this.optionsSignature = signature
            this.render()
            this.setupSentinelObserver()
            this.attachCursorReporting()
          },
          destroyed() {
            this.el.removeEventListener("keydown", this.onKeydown)
            this.el.removeEventListener("mousedown", this.onOptionMouseDown)
            this.sentinelObserver?.disconnect()
            this.detachCursorReporting()
            // Only the winning registration ever owns the registry entry
            // (see registerChord) — a duplicate loser has nothing to undo.
            if (this.chordSignature && window.__flickerChordRegistry.get(this.chordSignature) === this) {
              window.__flickerChordRegistry.delete(this.chordSignature)
            }
          },
          // Real cursor-position reporting (Spec 003's cursor-tracking
          // follow-up, now closed): `keyup` sets a `phx-value-cursor`
          // attribute directly on the input, synchronously, before the
          // event bubbles to LiveView's own delegated `phx-keyup`
          // listener — so the debounced "query" push (bound on the
          // input's own `phx-keyup`) always carries the cursor position
          // for the *same* keystroke it carries the value for, never a
          // stale one from an earlier or later event. `click`/`select`
          // don't change the typed value at all (nothing for "query" to
          // debounce), so they push their own lightweight "cursor" event
          // immediately. Idempotent, and safe to call again from
          // `updated()`: the input node itself gets replaced as results
          // re-render (see the comment on `this.onKeydown`'s attachment
          // above), which would silently drop a listener bound directly to
          // it — re-attaching only when the node actually changed keeps
          // this cheap on the common case (same node).
          attachCursorReporting() {
            const input = this.input()
            if (!input || input === this.cursorInput) return
            this.detachCursorReporting()
            this.cursorInput = input
            this.onKeyupCursor = () => input.setAttribute("phx-value-cursor", String(input.selectionStart))
            this.onClickOrSelectCursor = () => this.pushEventTo(this.el, "cursor", { cursor: input.selectionStart })
            input.addEventListener("keyup", this.onKeyupCursor)
            input.addEventListener("click", this.onClickOrSelectCursor)
            input.addEventListener("select", this.onClickOrSelectCursor)
          },
          detachCursorReporting() {
            if (!this.cursorInput) return
            this.cursorInput.removeEventListener("keyup", this.onKeyupCursor)
            this.cursorInput.removeEventListener("click", this.onClickOrSelectCursor)
            this.cursorInput.removeEventListener("select", this.onClickOrSelectCursor)
            this.cursorInput = null
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
            // ArrowDown already sitting on the last option, in a `paginate`
            // listbox — Spec 010: keyboard users get the same "reaching the
            // tail loads the next window" behaviour scrolling gets, via the
            // same debounced `load-more` event the sentinel observer uses.
            const atEnd = delta > 0 && this.activeIndex >= options.length - 1
            this.activeIndex = Math.max(0, Math.min(options.length - 1, next))
            this.render()
            if (atEnd && this.el.dataset.paginate === "true") this.requestLoadMore()
          },
          // Debounced server-side (the `load-more` handler ignores a
          // request while a window is already loading or the list is
          // complete) — a held ArrowDown key-repeats this, and the
          // IntersectionObserver can re-fire while the sentinel stays
          // visible, but only the first request past each completed fetch
          // does anything (Spec 010's resolved "queued keypresses collapse"
          // open question).
          requestLoadMore() {
            this.pendingLoadMore = true
            this.pushEventTo(this.el, "load-more", {})
          },
          setupSentinelObserver() {
            this.sentinelObserver?.disconnect()
            const sentinel = this.el.querySelector("[data-flicker-sentinel]")
            if (!sentinel) return
            const listbox = sentinel.closest('[role="listbox"]')
            this.sentinelObserver = new IntersectionObserver(
              entries => {
                if (entries.some(entry => entry.isIntersecting)) this.requestLoadMore()
              },
              { root: listbox }
            )
            this.sentinelObserver.observe(sentinel)
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
            // `option_active` theme values are class *lists* ("bg-indigo-100
            // text-indigo-900" in the Tailwind preset) — classList.toggle
            // takes one token at a time and throws on whitespace, so split
            // (caught by Spec 007's browser suite: the highlight crashed the
            // hook on every multi-class theme).
            const activeClasses = activeClass ? activeClass.split(/\s+/).filter(Boolean) : []
            this.options().forEach((option, i) => {
              const active = i === this.activeIndex
              option.setAttribute("aria-selected", active ? "true" : "false")
              const button = option.querySelector("button")
              if (button) activeClasses.forEach(cls => button.classList.toggle(cls, active))
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
