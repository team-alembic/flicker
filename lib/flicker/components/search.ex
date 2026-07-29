defmodule Flicker.Components.Search do
  @moduledoc """
  The internal `Phoenix.LiveComponent` behind `Flicker.search/1`
  ([Spec 003](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-003-faceted-search.md)).

  This module is not part of the public API — hosts never reference it
  directly. `Flicker.search/1` is the only supported entry point.

  Unlike `Flicker.Components.Select`, this component has **no selection
  semantics** and never lists/fetches records itself: it owns only the
  typed text, classifies the cursor position on every keystroke via
  `Flicker.CursorContext`, and drives a suggestion dropdown off
  `Flicker.FacetSuggest` — facet-key suggestions, an enum facet's value
  picklist, or a relationship facet's nested actor-scoped record search.
  Every keystroke re-parses the full text (`Flicker.Query.parse/2`) and
  sends `{on_change, query, filter}` to the host — the host owns what it
  does with the composed query (drive a Cinder table, a stream, its own
  list).

  The `.FlickerSearchNav` colocated hook reports the input's real
  `selectionStart` on every keyup/click/select (Spec 003's cursor-tracking
  follow-up, now closed) — the `cursor` assign carries it (`nil` before
  the hook's first event, or after this component sets the text itself,
  falling back to end-of-text per `Flicker.FacetSuggest.classify/3`), so a
  cursor moved back into an already-typed token classifies right there,
  not "at the end".
  """

  use Phoenix.LiveComponent

  alias Flicker.{Correction, CursorContext, Dispatch, FacetSuggest, Messages, Query, RecentValues}
  alias Flicker.Facet.Format

  require Logger

  @impl true
  # `:text` is popped out of `assigns` before the blanket `assign/2` below so
  # it's adopted only via `assign_new/3` (Spec 009 Level 2's `text` attr on
  # `Flicker.search/1`, for restoring a URL-serialised search on mount) —
  # once this component's own socket has a `:text` assign (from its own
  # `mount/1`-less first `update/2`, or any later `handle_event` typing),
  # `assign_new/3` is a no-op regardless of what the host keeps passing in,
  # so a host that doesn't clear its `text:` attr after mount can't clobber
  # what the user types next.
  def update(assigns, socket) do
    {initial_text, assigns} = Map.pop(assigns, :text)

    socket = assign(socket, assigns)
    facets = socket.assigns.facets

    socket =
      socket
      # A restored input (Spec 009 Level 2's `text` attr) is split on first
      # mount: its already-complete facet tokens become committed pills, only
      # its free-text remainder stays in the input buffer — same end state a
      # user reaches by typing them. `assign_new/3` means later renders never
      # re-split (they'd clobber what the user has typed since).
      |> assign_new(:committed, fn -> initial_committed(initial_text, facets) end)
      |> assign_new(:text, fn -> initial_buffer(initial_text, facets) end)
      |> assign_new(:cursor, fn -> nil end)
      |> assign_new(:open, fn -> false end)
      |> assign_new(:suggestions_loading, fn -> false end)
      |> assign_new(:dispatch, fn -> :debounce end)
      |> assign_new(:on_invalid, fn -> :drop end)
      |> assign_new(:count_source, fn -> nil end)
      |> assign_new(:recent_values, fn -> nil end)
      # Spec 019: the open editor's whole state, or nil. One assign, one place
      # to look — nothing else in this component branches on editor state, and
      # there is at most one open at a time.
      |> assign_new(:facet_editor, fn -> nil end)
      |> assign_new(:facet_counts, fn -> %{} end)
      # The free text most recently handed to the host, as opposed to typed —
      # `Flicker.Dispatch.pending?/3` compares the pair to decide whether
      # `:enter`'s "press Enter to search" affordance is showing (Spec 020).
      |> assign_new(:dispatched_text, fn -> "" end)
      |> assign(:connected?, Phoenix.LiveView.connected?(socket))
      |> refresh_context()

    {:ok, socket}
  end

  defp initial_committed(nil, _facets), do: []
  defp initial_committed(text, facets), do: Query.parse(text, facets).facets

  defp initial_buffer(nil, _facets), do: ""
  defp initial_buffer(text, facets), do: Query.parse(text, facets).text

  # `phx-keyup` fires for *every* key — including the Enter/Escape keydowns
  # the `.FlickerSearchNav` hook has already turned into a
  # suggestion-insert/close — and that trailing keyup races the resulting
  # server round trip, smuggling a stale `value` into a "query" event that
  # clobbers the just-inserted facet token (or reopens the just-closed
  # suggestions) a debounce later. Neither key can have edited the text, so
  # their keyups are ignored outright — same guard, same reasoning, as
  # `Flicker.Components.Select`'s.
  @impl true
  def handle_event("query", %{"key" => key}, socket) when key in ["Enter", "Escape", "Tab"], do: {:noreply, socket}

  def handle_event("query", %{"value" => text} = params, socket) do
    committed_before = socket.assigns.committed

    socket =
      socket
      |> assign(
        text: text,
        cursor: CursorContext.parse_selection_start(params["cursor"]),
        open: true
      )
      |> absorb_committed()
      |> refresh_context()
      |> notify_change(:input)

    # If a completed facet token was just lifted out of the buffer into a
    # pill, the input's DOM value still carries it — push the trimmed buffer
    # back so the token visibly moves from the input into the pill row.
    socket =
      if socket.assigns.committed == committed_before,
        do: socket,
        else: focus_input(socket, socket.assigns.text)

    {:noreply, socket}
  end

  # A cursor moving without the text changing (a click, or a keyboard/mouse
  # selection change with no typing) — no facets configured means there's
  # no context to reclassify, so this is a no-op rather than redoing the
  # same free-text state for nothing.
  def handle_event("cursor", _params, %{assigns: %{facets: []}} = socket), do: {:noreply, socket}

  def handle_event("cursor", %{"cursor" => cursor}, socket) do
    socket =
      socket
      |> assign(cursor: CursorContext.parse_selection_start(cursor))
      |> refresh_context()

    {:noreply, socket}
  end

  # Choosing a facet *key* for a facet that has an editor opens the editor
  # straight away rather than inserting `status:` and waiting. This is the
  # biggest discoverability win available (Spec 019): the user learns the rich
  # control exists by doing the thing they were already doing.
  def handle_event("select_suggestion", %{"insert" => insert}, socket) do
    case editor_for_key_insert(socket, insert) do
      nil -> do_select_suggestion(socket, insert)
      {facet, editor} -> {:noreply, open_editor(socket, facet, editor, insert)}
    end
  end

  def handle_event("facet_editor_cancel", _params, socket) do
    # Cancel discards the draft and restores the token exactly as it was, so
    # nothing is dispatched and nothing about the query changed.
    {:noreply, focus_input(assign(socket, :facet_editor, nil), socket.assigns.text)}
  end

  # The one commit. Splices canonical token text through the same path as any
  # suggestion, closes the pop-out, and dispatches exactly once.
  def handle_event("facet_editor_commit", %{"insert" => insert}, socket) do
    socket |> assign(:facet_editor, nil) |> do_select_suggestion(insert)
  end

  # Multi mode accumulates in the draft and commits once, so widening a
  # selection is one dispatch rather than one per checkbox.
  def handle_event("facet_editor_toggle", %{"value" => raw}, socket) do
    with %{facet: facet, value: value} <- socket.assigns.facet_editor,
         {:ok, _op, parsed} <- Flicker.Facet.cast_value(facet, raw, facet.default_op) do
      selected = List.wrap(value)

      toggled =
        if parsed in selected, do: List.delete(selected, parsed), else: selected ++ [parsed]

      {:noreply, update_editor(socket, %{value: toggled})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("facet_editor_month", %{"month" => month}, socket) do
    case Date.from_iso8601(month) do
      {:ok, date} -> {:noreply, update_editor(socket, %{month: Date.beginning_of_month(date)})}
      _error -> {:noreply, socket}
    end
  end

  # Picking a day: the first sets a draft start, the second completes the range
  # and commits. Nothing dispatches in between — a half-made selection is a
  # draft, visible only in the footer (ADR-011).
  def handle_event("facet_editor_pick", %{"date" => date}, socket) do
    with %{facet: facet, editor: editor} = state <- socket.assigns.facet_editor,
         {:ok, picked} <- Date.from_iso8601(date) do
      pick_day(socket, state, facet, editor, picked)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("facet_editor_input", params, socket) do
    with %{facet: facet, editor: editor} <- socket.assigns.facet_editor,
         token when is_binary(token) <- endpoints_token(facet, params) do
      case editor.parse(token, facet) do
        {:ok, value} -> {:noreply, update_editor(socket, %{value: value})}
        :error -> {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("remove_facet", %{"index" => index}, socket) do
    committed = List.delete_at(socket.assigns.committed, String.to_integer(index))

    socket =
      socket
      |> assign(committed: committed)
      |> refresh_context()
      |> notify_change()

    {:noreply, focus_input(socket, socket.assigns.text)}
  end

  # Backspace on an empty buffer removes the last committed pill (mirrors the
  # multi-select chip behaviour) — the `.FlickerSearchNav` hook only pushes
  # this when the input is empty, so ordinary Backspace still edits text.
  def handle_event("remove_last_facet", _params, %{assigns: %{text: "", committed: [_ | _] = committed}} = socket) do
    socket =
      socket
      |> assign(committed: List.delete_at(committed, -1))
      |> refresh_context()
      |> notify_change()

    {:noreply, socket}
  end

  def handle_event("remove_last_facet", _params, socket), do: {:noreply, socket}

  # Spec 020's `:enter` policy: the only route by which held text reaches the
  # host. `:enter` as the trigger is what `Flicker.Dispatch.dispatch?/4` lets
  # through where `:input` was withheld.
  def handle_event("dispatch_query", _params, socket), do: {:noreply, notify_change(socket, :enter)}

  # Spec 023: accepting a correction or a mechanical fix. Deliberately the same
  # splice as any other suggestion (`select_suggestion` above) — a correction
  # emits canonical token text and nothing about applying one is special.
  def handle_event("accept_correction", %{"insert" => insert}, socket) do
    handle_event("select_suggestion", %{"insert" => insert}, socket)
  end

  def handle_event("focus", _params, socket), do: {:noreply, assign(socket, open: true)}

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, open: false)}

  def handle_event("clear", _params, socket) do
    socket =
      socket
      |> assign(text: "", committed: [], cursor: nil, open: false)
      |> refresh_context()
      |> notify_change()

    {:noreply, focus_input(socket, "")}
  end

  @impl true
  def handle_async(:related_search, {:ok, {:ok, suggestions}}, socket) do
    {:noreply, assign(socket, suggestions: suggestions, suggestions_loading: false)}
  end

  def handle_async(:related_search, {:ok, {:error, reason}}, socket) do
    Logger.warning("Flicker facet related search failed: #{inspect(reason)}")
    {:noreply, assign(socket, suggestions: [], suggestions_loading: false)}
  end

  # `cancel_async/2`'s default exit reason — the synchronous branches of
  # `load_suggestions/2` cancel a stale in-flight related search this way
  # before assigning their own suggestions. `Process.exit/2` kills the task
  # but doesn't un-track its ref, so this callback still runs once the kill
  # signal lands; without this clause it would clobber the just-rendered
  # suggestions with an empty list a moment later. Any other exit reason is
  # a genuine crash, still logged and cleared.
  def handle_async(:related_search, {:exit, {:shutdown, :cancel}}, socket), do: {:noreply, socket}

  def handle_async(:related_search, {:exit, reason}, socket) do
    Logger.warning("Flicker facet related search task exited: #{inspect(reason)}")
    {:noreply, assign(socket, suggestions: [], suggestions_loading: false)}
  end

  def handle_async(:facet_counts, {:ok, {:ok, counts}}, socket) do
    {:noreply, assign(socket, :facet_counts, counts)}
  end

  # A failed count must never break a working search (Spec 021): logged at
  # debug, swallowed, no number rendered.
  def handle_async(:facet_counts, {:ok, {:error, reason}}, socket) do
    Logger.debug("Flicker facet counts failed: #{inspect(reason)}")

    {:noreply, assign(socket, :facet_counts, %{})}
  end

  def handle_async(:facet_counts, {:exit, reason}, socket) do
    Logger.debug("Flicker facet counts exited: #{inspect(reason)}")

    {:noreply, assign(socket, :facet_counts, %{})}
  end

  defp refresh_context(socket) do
    facets = socket.assigns.facets
    context = FacetSuggest.classify(socket.assigns.text, facets, socket.assigns.cursor)

    socket
    |> assign(:context, context)
    |> load_suggestions(context)
  end

  defp load_suggestions(socket, {:key, prefix}) do
    suggestions = FacetSuggest.key_suggestions(prefix, socket.assigns.facets)

    socket
    |> cancel_async(:related_search)
    |> assign(suggestions: suggestions, suggestions_loading: false)
  end

  # A relationship facet's `:related` is itself an Ash-only concept
  # (ADR-006) — `FacetSuggest.related_search/3` only compiles when `ash` is
  # present, so this clause only exists then too. Without `ash`, a
  # relationship facet can't be configured in the first place, so the plain
  # `{:value, facet, prefix}` clause below (empty picklist) is the correct
  # fallback rather than referencing an undefined function.
  if Code.ensure_loaded?(Ash) do
    defp load_suggestions(socket, {:value, %{related: related} = facet, prefix}) when not is_nil(related) do
      actor = socket.assigns[:actor]
      tenant = socket.assigns[:tenant]
      limit = socket.assigns[:limit]

      socket
      |> assign(suggestions_loading: true)
      |> start_async(:related_search, fn ->
        FacetSuggest.related_search(facet, prefix, actor: actor, tenant: tenant, limit: limit)
      end)
    end
  end

  defp load_suggestions(socket, {:value, facet, prefix}) do
    # Recent values sit above the ordinary picklist, deduplicated against it so
    # the same value never appears twice on screen.
    recent = recent_suggestions(socket, facet, prefix)
    recent_values = MapSet.new(recent, & &1.value)

    suggestions =
      recent ++
        Enum.reject(
          FacetSuggest.enum_value_suggestions(facet, prefix),
          &MapSet.member?(recent_values, &1.value)
        )

    socket
    |> cancel_async(:related_search)
    |> assign(suggestions: suggestions, suggestions_loading: false)
  end

  defp load_suggestions(socket, :text) do
    socket |> cancel_async(:related_search) |> assign(suggestions: [], suggestions_loading: false)
  end

  # For this component the host notification *is* the dispatch — it owns no
  # provider of its own — so Spec 020's policy gates `send/2` here, the one
  # funnel every path goes through.
  #
  # The default trigger is `:facet_commit`: inserting a suggestion, removing a
  # pill, and clearing are all deliberate discrete acts that dispatch under
  # every policy. Only the typing path passes `:input`.
  # Spec 021: counts ride alongside the query rather than blocking it. Results
  # (here, the host's own notification) go out first; the counts land when they
  # land and fill in. `start_async/3` keyed on `:facet_counts` inherits the same
  # last-write-wins supersession `:search` gets, so a stale tally can't render
  # against a newer query.
  defp maybe_count(socket) do
    counted = Enum.filter(socket.assigns.facets, & &1.count)

    if counted == [] or is_nil(socket.assigns.count_source) do
      socket
    else
      provider = socket.assigns.count_source
      query = combined_query(socket, socket.assigns.facets)
      opts = [actor: socket.assigns[:actor], tenant: socket.assigns[:tenant]]

      start_async(socket, :facet_counts, fn ->
        Flicker.Provider.run_facet_counts(provider, query, counted, opts)
      end)
    end
  end

  defp notify_change(socket, trigger \\ :facet_commit) do
    facets = socket.assigns.facets

    if Dispatch.dispatch?(socket.assigns.dispatch, trigger, socket.assigns.text, 0) and
         not withholding?(socket) do
      query = combined_query(socket, facets)
      filter = to_filter(query, facets)

      send(self(), {socket.assigns.on_change, query, filter})

      socket
      |> assign(:dispatched_text, socket.assigns.text)
      |> maybe_count()
    else
      socket
    end
  end

  defp do_select_suggestion(socket, insert) do
    new_text =
      FacetSuggest.replace_current_token(socket.assigns.text, insert, socket.assigns.cursor)

    record_committed(socket, insert)

    socket =
      socket
      # `cursor: nil` keeps the server's classification of "where the caret
      # is" in sync with end-of-text, matching what `focus_input/2` (below)
      # actually puts in the DOM, rather than reclassifying against a
      # now-stale mid-token position.
      |> assign(text: new_text, cursor: nil, open: true)
      |> absorb_committed()
      |> refresh_context()
      |> notify_change()

    {:noreply, focus_input(socket, socket.assigns.text)}
  end

  defp facet_editor_label(%{facet_editor: %{facet: facet}}) do
    facet.label || humanize(to_string(facet.key))
  end

  defp facet_editor_label(_assigns), do: nil

  # Every editor gets the same assigns shape, so adding one needs no changes
  # here — a host's own editor module is indistinguishable from a built-in.
  defp facet_editor_content(%{facet_editor: %{editor: editor} = state} = assigns) do
    editor.render(%{
      id: assigns.input_id,
      facet: state.facet,
      value: state.value,
      value_from: range_part(state.value, :from),
      value_to: range_part(state.value, :to),
      value_preset: range_part(state.value, :preset),
      from_percent: Flicker.FacetEditor.Dial.thumb_percent(range_part(state.value, :from), state.facet.bounds),
      to_percent: Flicker.FacetEditor.Dial.thumb_percent(range_part(state.value, :to), state.facet.bounds),
      bounds: state.facet.bounds,
      month: state.month,
      today: state.today,
      draft_start: state.draft_start,
      hover: state.hover,
      first_day_of_week: 1,
      presets: state.facet.presets || Flicker.Facet.Preset.builtin(),
      suggested: state.facet.suggested || [],
      footer: facet_editor_footer(state),
      labels: %{
        suggested: "Suggested",
        previous_month: "Previous month",
        next_month: "Next month",
        from: "From",
        to: "To",
        values: "Values",
        done: "Done"
      },
      theme: assigns.theme,
      select_theme: assigns.theme,
      messages: assigns[:messages],
      candidates: editor_candidates(state.facet),
      selected: List.wrap(state.value),
      counts: Map.get(assigns.facet_counts, state.facet.key, %{}),
      done_token: done_token(state),
      actor: assigns[:actor],
      tenant: assigns[:tenant],
      toggled_token: "#{state.facet.key}:#{state.value != true} ",
      disabled: not assigns.connected?,
      target: assigns.myself
    })
  end

  defp facet_editor_content(_assigns), do: nil

  # A draft says so in words rather than leaving the control looking inert; a
  # complete value shows itself.
  defp facet_editor_footer(%{editor: editor, facet: facet, value: value, draft_start: draft_start}) do
    draft = if draft_start, do: %Flicker.Facet.Range{from: draft_start}, else: value

    cond do
      # Same loaded-module caveat as `Flicker.FacetEditor.modal?/1`.
      Code.ensure_loaded?(editor) and function_exported?(editor, :draft_label, 3) and
          editor.draft_label(draft, facet, []) ->
        editor.draft_label(draft, facet, [])

      is_nil(value) ->
        ""

      true ->
        Format.value_label(facet, value)
    end
  end

  # The candidate list comes from `value_source/1`, so an enum editor and a
  # relationship editor are the same code with a different provider behind them.
  # A local `Static` source resolves synchronously — which is why opening an
  # enum editor costs no round trip at all.
  defp editor_candidates(facet) do
    case Flicker.Facet.value_source(facet) do
      {Flicker.Providers.Static, results: results} -> results
      _other -> []
    end
  end

  defp done_token(%{facet: facet, editor: editor, value: value}) do
    Flicker.FacetEditor.to_token(editor, List.wrap(value), facet)
  end

  defp range_part(%Flicker.Facet.Range{} = range, part), do: Map.get(range, part)
  defp range_part(_value, _part), do: nil

  # -- Facet editors (Spec 019) -------------------------------------------

  # A key suggestion looks like `status:` — nothing after the operator. Only
  # those open an editor, and only for a facet whose editor wants a pop-out.
  defp editor_for_key_insert(socket, insert) do
    with true <- String.ends_with?(insert, ":"),
         key_text = String.trim_trailing(insert, ":"),
         {:ok, key} <- existing_atom(key_text),
         facet when not is_nil(facet) <- Enum.find(socket.assigns.facets, &(&1.key == key)),
         true <- Flicker.FacetEditor.modal?(facet) do
      {facet, Flicker.FacetEditor.for_facet(facet)}
    else
      _ -> nil
    end
  end

  defp open_editor(socket, facet, editor, insert) do
    today = Date.utc_today()

    assign(socket, :facet_editor, %{
      facet: facet,
      editor: editor,
      value: initial_editor_value(facet),
      month: Date.beginning_of_month(today),
      today: today,
      draft_start: nil,
      hover: nil,
      insert: insert
    })
  end

  # Reopening a committed facet starts from its current value; a fresh open
  # starts empty.
  defp initial_editor_value(%{type: type}) when type in [:date_range, :datetime_range, :number_range],
    do: %Flicker.Facet.Range{}

  defp initial_editor_value(%{multiple?: true}), do: []
  defp initial_editor_value(_facet), do: nil

  defp update_editor(socket, changes) do
    case socket.assigns.facet_editor do
      nil -> socket
      state -> assign(socket, :facet_editor, Map.merge(state, changes))
    end
  end

  # First pick sets the draft start; second completes and commits. Endpoints
  # swap if the second pick is earlier, so there is no wrong order to get into.
  defp pick_day(socket, %{draft_start: nil}, facet, _editor, picked) do
    if range_facet?(facet) do
      {:noreply, update_editor(socket, %{draft_start: picked, hover: picked})}
    else
      commit_editor_value(socket, facet, Flicker.FacetEditor.for_facet(facet), picked)
    end
  end

  defp pick_day(socket, %{draft_start: start}, facet, editor, picked) do
    {from, to} = if Date.before?(picked, start), do: {picked, start}, else: {start, picked}

    commit_editor_value(socket, facet, editor, %Flicker.Facet.Range{from: from, to: to})
  end

  defp commit_editor_value(socket, facet, editor, value) do
    case Flicker.FacetEditor.to_token(editor, value, facet) do
      nil -> {:noreply, update_editor(socket, %{value: value})}
      token -> socket |> assign(:facet_editor, nil) |> do_select_suggestion(token)
    end
  end

  defp range_facet?(facet), do: Flicker.Facet.range?(facet)

  # The dial's two inputs become one range literal, with a blank meaning open —
  # which is how "over 100" stays expressible from the text side too.
  defp endpoints_token(facet, params) do
    from = params |> Map.get("from", "") |> String.trim()
    to = params |> Map.get("to", "") |> String.trim()

    if !(from == "" and to == "") do
      if range_facet?(facet), do: "#{from}..#{to}", else: from
    end
  end

  # Spec 022: recorded on *commit* only — a chosen suggestion. Not on hover, not
  # on focus, not per keystroke, and never for a value that failed validation
  # (an invalid token never parses into `:facets`, so it can't reach here).
  defp record_committed(socket, insert) do
    query = Query.parse(String.trim(insert), socket.assigns.facets)
    opts = [actor: socket.assigns[:actor], tenant: socket.assigns[:tenant]]

    Enum.each(query.facets, fn {key, _op, value} ->
      RecentValues.record(socket.assigns.recent_values, key, value, opts)
    end)
  end

  # Spec 022: a `Recent` group above the ordinary values, shown only with an
  # empty prefix. Once someone is typing they have said what they want, and a
  # recency group is then just a duplicate row above the match.
  #
  # Every remembered value is re-checked before it is offered: an enum value no
  # longer in the facet's `:values` is dropped, and a value that no longer casts
  # is dropped. A recency store is a hint, never a bypass — and a dropped value
  # is dropped *silently*, since "you used this before but can't see it now" is
  # itself a disclosure.
  defp recent_suggestions(_socket, _facet, prefix) when prefix != "", do: []

  defp recent_suggestions(socket, facet, _prefix) do
    opts = [actor: socket.assigns[:actor], tenant: socket.assigns[:tenant]]

    socket.assigns.recent_values
    |> RecentValues.load(facet.key, opts)
    |> Enum.filter(&still_offerable?(facet, &1))
    |> Enum.map(&recent_suggestion(facet, &1))
  end

  defp still_offerable?(%{values: values}, value) when is_list(values), do: value in values

  defp still_offerable?(facet, value) do
    match?(
      {:ok, _op, _value},
      Flicker.Facet.cast_value(facet, to_string(value), facet.default_op)
    )
  end

  defp recent_suggestion(facet, value) do
    insert = "#{facet.key}:#{value} "

    %Flicker.Result{
      value: "#{facet.key}:#{value}",
      label: Format.value_label(facet, value),
      sublabel: nil,
      meta: %{flicker_facet: true, insert: insert, recent: true}
    }
  end

  # The count for a value suggestion, or `nil` when this facet isn't counted or
  # the value wasn't in the tally. `nil` and `0` are deliberately different: no
  # count renders nothing, a zero renders `0` and dims the row.
  defp suggestion_count(assigns, %{meta: %{insert: insert}}) do
    with [key_text, value_text] <- String.split(String.trim(insert), ":", parts: 2),
         {:ok, key} <- existing_atom(key_text),
         %{} = tally <- Map.get(assigns.facet_counts, key),
         facet when not is_nil(facet) <- Enum.find(assigns.facets, &(&1.key == key)),
         {:ok, _op, value} <- Flicker.Facet.cast_value(facet, value_text, facet.default_op) do
      Map.get(tally, value)
    else
      _ -> nil
    end
  end

  defp suggestion_count(_assigns, _suggestion), do: nil

  defp existing_atom(string) do
    {:ok, String.to_existing_atom(string)}
  rescue
    ArgumentError -> :error
  end

  # One string, so assistive tech reads the label and its count together.
  defp suggestion_aria_label(assigns, suggestion) do
    case suggestion_count(assigns, suggestion) do
      nil -> nil
      count -> "#{suggestion.label}, #{message(assigns, :results_count, %{count: count})}"
    end
  end

  # Both hints can be live at once, and `aria-describedby` takes a list — so
  # the error and the press-Enter affordance are both announced rather than one
  # silently winning.
  defp describedby(input_id, invalid_report, dispatch_pending) do
    [
      invalid_report && "#{input_id}-facet-error",
      dispatch_pending && "#{input_id}-dispatch-hint"
    ]
    |> Enum.filter(& &1)
    |> case do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  # Spec 023's `on_invalid: :require`: withhold the whole query while a facet
  # value is broken, for hosts where a partially-applied filter is worse than
  # no update. `:drop` (the default) withholds nothing — ADR-012's per-facet
  # independence already keeps the bad token out of the filter, so the rest of
  # the query runs.
  defp withholding?(%{assigns: %{on_invalid: :require}} = socket), do: blocking_invalid(socket) != []

  defp withholding?(_socket), do: false

  # Every invalid token in the buffer, in order.
  defp invalid_tokens(socket) do
    Query.parse(socket.assigns.text, socket.assigns.facets).invalid
  end

  # The token the caret currently sits inside is exempt from the `:require`
  # gate: half-typed input is *expected* to be invalid, and blocking dispatch
  # on every keystroke of `status:a`, `status:ac` would make the policy
  # unusable. It still renders its error — it just doesn't withhold the query.
  defp blocking_invalid(socket) do
    in_progress = token_at_cursor(socket)

    socket |> invalid_tokens() |> Enum.reject(&(&1.token == in_progress))
  end

  defp token_at_cursor(%{assigns: %{text: text, cursor: cursor}}) do
    codepoint_cursor =
      case cursor do
        nil -> String.length(text)
        value -> CursorContext.from_utf16_offset(text, value)
      end

    {start, stop} = CursorContext.token_bounds(text, codepoint_cursor)

    String.slice(text, start, stop - start)
  end

  # The first invalid token, with its message, its mechanical fix, and any
  # suggested replacements — everything the error region needs to render.
  defp invalid_report(socket) do
    case invalid_tokens(socket) do
      [] ->
        nil

      [invalid | _rest] ->
        facet = Enum.find(socket.assigns.facets, &(&1.key == invalid.key))
        messages = socket.assigns[:messages]

        explained = Correction.explain(facet, invalid.reason, invalid.params, messages: messages)

        %{
          invalid: invalid,
          facet: facet,
          message: explained.message,
          fix: explained.fix,
          fix_token: Correction.to_token(facet, explained.fix),
          candidates:
            Enum.map(
              Correction.candidates(facet, invalid.raw, invalid.reason, invalid.params),
              &%{correction: &1, token: Correction.to_token(facet, &1)}
            )
        }
    end
  end

  # The emitted query is the committed pills plus whatever's still in the
  # buffer: committed facets first, then the buffer's own parsed facets and
  # free text. `:input` is reconstructed (canonical committed tokens + the
  # raw buffer) so a re-`parse/2` (Spec 009's URL round-trip) reproduces it.
  defp combined_query(socket, facets) do
    buffer_query = Query.parse(socket.assigns.text, facets)
    committed = socket.assigns.committed

    %Query{
      text: buffer_query.text,
      facets: committed ++ buffer_query.facets,
      input: build_input(committed, socket.assigns.text)
    }
  end

  defp build_input(committed, buffer) do
    [Enum.map_join(committed, " ", &canonical_token/1), buffer]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  # Lifts every complete facet token out of the buffer into `:committed`,
  # leaving only free text (and any still-in-progress token) behind. A token
  # is complete once the buffer ends in whitespace — the "I've finished this"
  # signal, and exactly what the value-suggestion insert appends. Free-text-
  # only buffers (no facets to lift) are left untouched.
  defp absorb_committed(%{assigns: %{facets: []}} = socket), do: socket

  defp absorb_committed(socket) do
    buffer = socket.assigns.text

    if buffer != "" and Regex.match?(~r/\s\z/u, buffer) do
      parsed = Query.parse(buffer, socket.assigns.facets)

      case parsed.facets do
        [] ->
          socket

        facets ->
          assign(socket,
            committed: socket.assigns.committed ++ facets,
            text: parsed.text,
            cursor: nil
          )
      end
    else
      socket
    end
  end

  defp canonical_token({key, op, value}), do: "#{key}#{op_token(op)}#{value_token(value)}"

  defp op_token(:neq), do: "!="
  defp op_token(:gt), do: ">"
  defp op_token(:gte), do: ">="
  defp op_token(:lt), do: "<"
  defp op_token(:lte), do: "<="
  defp op_token(_default_op), do: ":"

  defp value_token(%Date{} = date), do: Date.to_iso8601(date)
  defp value_token(value) when is_binary(value), do: quote_if_needed(value)
  defp value_token(value), do: to_string(value)

  defp quote_if_needed(value) do
    if Regex.match?(~r/\s/u, value), do: ~s("#{value}"), else: value
  end

  # `Query.to_filter/2` only compiles when `ash` is present (ADR-006) — this
  # wrapper keeps that reference out of a no-ash build entirely, rather than
  # a runtime `if Code.ensure_loaded?(Ash)` that still leaves the reference
  # in the compiled module (and triggers "undefined function" as a warning
  # regardless of which branch runs).
  if Code.ensure_loaded?(Ash) do
    defp to_filter(query, facets), do: Query.to_filter(query, facets)
  else
    defp to_filter(_query, _facets), do: nil
  end

  # See `Flicker.Components.Select`'s identical helper for why this exists:
  # LiveView's DOM patching never touches a focused text input's `value`,
  # so reassigning `@text` to something the user didn't just type (an
  # inserted facet token, a cleared search) while the input keeps DOM focus
  # never reaches the browser through the ordinary render diff. Pushes
  # `phx:focusElementById` (handled in the `.FlickerSearchNav` hook below,
  # which shares its registration with `Flicker.Components.Select`'s) to
  # force-set it instead.
  defp focus_input(socket, value), do: push_event(socket, "focusElementById", %{id: input_id(socket), value: value})

  defp input_id(%Phoenix.LiveView.Socket{} = socket), do: input_id_for(socket.assigns.id)
  defp input_id(assigns), do: input_id_for(assigns.id)

  defp input_id_for(id), do: "#{id}-input"
  defp listbox_id_for(id), do: "#{id}-listbox"
  defp suggestion_id(assigns, index), do: "#{assigns.id}-suggestion-#{index}"

  defp message(assigns, key, bindings \\ %{}), do: Messages.get(assigns[:messages], key, bindings)

  defp context_message(assigns, {:key, _prefix}), do: message(assigns, :facet_key_context)

  defp context_message(assigns, {:value, facet, _prefix}),
    do: message(assigns, :facet_value_context, %{facet: facet_label(facet)})

  defp context_message(assigns, :text), do: message(assigns, :free_text_context)

  defp facet_label(%{label: nil, key: key}), do: to_string(key)
  defp facet_label(%{label: label}), do: label

  # A committed facet as a pill: `%{index, field, value}` where `field` is
  # the facet's display name and `value` its human label (enum `value_labels`
  # when present, otherwise humanised), with a non-`:eq` operator prefixed so
  # `monthly_listeners >= 100000` reads as "≥ 100000", not just "100000".
  defp build_pills(committed, facets) do
    committed
    |> Enum.with_index()
    |> Enum.map(fn {{key, op, value}, index} ->
      facet = Enum.find(facets, &(&1.key == key))

      %{
        index: index,
        field: pill_field(facet, key),
        value: pill_value(facet, op, value),
        color: value_color(facet, value)
      }
    end)
  end

  # Spec 017: a facet may declare a colour per value; the pill shows it as a
  # leading dot. Host-supplied strings (any CSS colour) — no built-in palette.
  defp value_color(%{value_colors: colors}, value) when is_map(colors), do: Map.get(colors, value)
  defp value_color(_facet, _value), do: nil

  defp pill_field(nil, key), do: humanize(to_string(key))
  defp pill_field(%{label: nil, key: key}, _key), do: humanize(to_string(key))
  defp pill_field(%{label: label}, _key), do: label

  # A free-value facet (numeric/date/string, no enum picklist or relationship
  # search) has no suggestions to offer in value position — so instead of the
  # bare "No results" empty state, the listbox shows a hint that a value can
  # just be typed, since that's the only way to complete these facets.
  defp value_hint(assigns, {:value, %{related: related, type: :date}, _prefix}) when is_nil(related),
    do: message(assigns, :facet_date_value_hint)

  defp value_hint(assigns, {:value, %{related: related, type: type}, _prefix})
       when is_nil(related) and type in [:integer, :float, :string],
       do: message(assigns, :facet_free_value_hint)

  defp value_hint(_assigns, _context), do: nil

  # A non-empty token that matches no facet key is just free text (it filters
  # the host's list, Spec 003) — don't pop a "No results" suggestion dropdown
  # for it. An empty key prefix (the freshly-focused input) still shows the
  # full facet-key list, and value positions keep their picklist/hint.
  defp free_text_key?({:key, prefix}, []) when prefix != "", do: true
  defp free_text_key?(_context, _suggestions), do: false

  defp pill_value(facet, op, value), do: op_prefix(op) <> value_display(facet, value)

  defp op_prefix(:between), do: ""
  defp op_prefix(:in), do: ""
  defp op_prefix(:not_in), do: "≠ "

  defp op_prefix(:neq), do: "≠ "
  defp op_prefix(:gt), do: "> "
  defp op_prefix(:gte), do: "≥ "
  defp op_prefix(:lt), do: "< "
  defp op_prefix(:lte), do: "≤ "
  defp op_prefix(_eq_or_contains), do: ""

  # Spec 018 introduced value shapes a pill can now hold that `to_string/1`
  # cannot render at all — a `Flicker.Facet.Range` has no String.Chars
  # implementation, and a list raises. Everything goes through
  # `Flicker.Facet.Format` instead, which also gets localised intervals and
  # conjunctions for free (ADR-013).
  defp value_display(nil, value), do: to_string(value)

  defp value_display(%{value_labels: labels} = facet, value) when is_map(labels) and is_atom(value) do
    Map.get(labels, value) || Format.value_label(facet, value)
  end

  defp value_display(facet, value) when is_atom(value) and not is_boolean(value) and not is_nil(value) do
    humanize(Format.value_label(facet, value))
  end

  defp value_display(facet, value), do: Format.value_label(facet, value)

  defp humanize(string) do
    case String.replace(string, "_", " ") do
      <<first::utf8, rest::binary>> -> String.upcase(<<first::utf8>>) <> rest
      other -> other
    end
  end

  defp suggestions_count_message(assigns, {:key, _prefix}),
    do: message(assigns, :facet_key_suggestions_count, %{count: length(assigns.suggestions)})

  defp suggestions_count_message(assigns, {:value, _facet, _prefix}),
    do: message(assigns, :facet_value_suggestions_count, %{count: length(assigns.suggestions)})

  defp suggestions_count_message(_assigns, :text), do: ""

  # The single live-region announcement (Spec 007), derived from exactly the
  # assigns that drive the visual render — see `Flicker.Components.Select`'s
  # `announcement/1` for the same design decision. Loading takes priority
  # over the context/count messages since the count isn't known yet; a
  # stale, slower response for an earlier keystroke can never land here
  # because `load_suggestions/2` cancels the previous `:related_search` task
  # by name before starting a new one.
  defp announcement(%{suggestions_loading: true} = assigns), do: message(assigns, :loading)

  defp announcement(assigns) do
    [
      context_message(assigns, assigns.context),
      suggestions_count_message(assigns, assigns.context)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  # Same bulletproof visually-hidden inline style as `Flicker.Components.Select`
  # (ADR-002 keeps Flicker stylesheet-free).
  @sr_only_style "position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; " <>
                   "overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0;"

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:input_id, input_id_for(assigns.id))
      |> assign(:listbox_id, listbox_id_for(assigns.id))
      |> assign(:sr_only_style, @sr_only_style)
      |> assign(
        :show_suggestions,
        assigns.open and assigns.context != :text and
          not free_text_key?(assigns.context, assigns.suggestions)
      )
      |> assign(:pills, build_pills(assigns.committed, assigns.facets))
      |> assign(:value_hint, value_hint(assigns, assigns.context))
      |> assign(
        :dispatch_pending,
        Dispatch.pending?(assigns.dispatch, assigns.text, assigns.dispatched_text)
      )
      |> assign(:labels_close, "Close")
      |> then(&assign(&1, :invalid_report, invalid_report(%{assigns: &1})))
      |> then(&assign(&1, :dispatch_withheld, &1.on_invalid == :require and &1.invalid_report != nil))

    assigns = assign(assigns, :announcement, announcement(assigns))

    ~H"""
    <div
      id={@id}
      class={@theme.wrapper}
      phx-hook=".FlickerSearchNav"
      phx-target={@myself}
      phx-click-away="close"
      data-active-class={@theme.option_active}
      data-dispatch={to_string(@dispatch)}
    >
      <%!--
        Committed facets are pills *inside* the field box (Spec 012), with
        the borderless input growing beside them and "clear all" centred in
        the box — a tokenised faceted input, not raw `key:value` text.
      --%>
      <div class={@theme.multi_field}>
        <div class={@theme.facet_pill_list} role="list" aria-label={message(assigns, :selected_items)}>
          <span :for={pill <- @pills} class={@theme.facet_pill} role="listitem" title={"#{pill.field}: #{pill.value}"}>
            <span
              :if={pill.color}
              aria-hidden="true"
              style={"background-color:#{pill.color}"}
              class="mr-1 inline-block h-2 w-2 shrink-0 rounded-full"
            >
            </span>
            <span class={@theme.facet_pill_value}>{pill.value}</span>
            <button
              type="button"
              class={@theme.facet_pill_remove}
              disabled={!@connected?}
              phx-click="remove_facet"
              phx-value-index={pill.index}
              phx-target={@myself}
              aria-label={message(assigns, :remove_chip, %{label: "#{pill.field} #{pill.value}"})}
            >
              {message(assigns, :remove_icon)}
            </button>
          </span>
        </div>
        <label id={"#{@input_id}-label"} for={@input_id} class="flicker-sr-only" style={@sr_only_style}>
          {message(assigns, :facet_search_placeholder)}
        </label>
        <input
          type="text"
          id={@input_id}
          name={"#{@id}-query"}
          role="combobox"
          aria-expanded={to_string(@show_suggestions)}
          aria-controls={@listbox_id}
          aria-autocomplete="list"
          aria-haspopup="listbox"
          autocomplete="off"
          class={@theme.multi_input}
          value={@text}
          placeholder={message(assigns, :facet_search_placeholder)}
          disabled={!@connected?}
          aria-invalid={@invalid_report && "true"}
          aria-describedby={describedby(@input_id, @invalid_report, @dispatch_pending)}
          phx-keyup="query"
          phx-debounce={Dispatch.debounce_attr(@dispatch, @debounce)}
          phx-focus="focus"
          phx-target={@myself}
        />
        <button
          :if={@text != "" or @pills != []}
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
      <%!-- Spec 019: the editor is a modal sub-context. `role="dialog"` and
      `aria-modal` say so, the main picker's keyboard model is suspended while
      it's open, and nothing dispatches until it commits (ADR-011). --%>
      <div
        :if={@facet_editor}
        id={"#{@input_id}-facet-editor"}
        role="dialog"
        aria-modal="true"
        aria-label={facet_editor_label(assigns)}
        class={@theme.facet_editor}
        phx-window-keydown="facet_editor_cancel"
        phx-key="Escape"
        phx-target={@myself}
      >
        <div class={@theme.facet_editor_header}>
          <span>{facet_editor_label(assigns)}</span>
          <button
            type="button"
            aria-label={@labels_close}
            disabled={!@connected?}
            phx-click="facet_editor_cancel"
            phx-target={@myself}
          >
            ✕
          </button>
        </div>
        {facet_editor_content(assigns)}
      </div>
      <%!-- Spec 023: an invalid facet value renders as *text*, with an icon —
      never colour alone, never a tooltip, never hover-only. ADR-012's whole
      trade (drop the bad clause, run the rest) depends on this being
      conspicuous, since the alternative is a silently broader result set. --%>
      <div :if={@invalid_report} id={"#{@input_id}-facet-error"}>
        <p class={@theme.facet_error_message}>
          <span class={@theme.facet_error_icon} aria-hidden="true">⚠</span>
          <span class={@theme.facet_pill_invalid}>{@invalid_report.invalid.token}</span>
          {@invalid_report.message}
        </p>
        <p :if={@invalid_report.fix_token} class={@theme.facet_correction}>
          <button
            type="button"
            class={@theme.facet_correction_accept}
            disabled={!@connected?}
            phx-click="accept_correction"
            phx-value-insert={@invalid_report.fix_token}
            phx-target={@myself}
          >
            {message(assigns, :apply_fix)}
          </button>
        </p>
        <p :if={@invalid_report.candidates != []} class={@theme.facet_correction}>
          <%= for {candidate, index} <- Enum.with_index(@invalid_report.candidates) do %>
            <button
              type="button"
              class={@theme.facet_correction_accept}
              disabled={!@connected?}
              phx-click="accept_correction"
              phx-value-insert={candidate.token}
              phx-target={@myself}
            >
              <%= if index == 0 do %>
                {message(assigns, :did_you_mean, %{label: candidate.correction.label})}
              <% else %>
                {candidate.correction.label}
              <% end %>
            </button>
          <% end %>
        </p>
        <p :if={@dispatch_withheld} class={@theme.dispatch_blocked}>
          {message(assigns, :dispatch_blocked)}
        </p>
      </div>
      <%!-- Spec 020: under `dispatch: :enter`, typed-but-undispatched text has
      to say so — visible text, referenced by the input's `aria-describedby`
      while it shows. --%>
      <p :if={@dispatch_pending} id={"#{@input_id}-dispatch-hint"} class={@theme.dispatch_hint}>
        {message(assigns, :press_enter_to_search)}
      </p>
      <div id={"#{@id}-announcer"} aria-live="polite" class="flicker-sr-only" style={@sr_only_style}>
        {@announcement}
      </div>
      <ul :if={@show_suggestions} id={@listbox_id} role="listbox" aria-labelledby={"#{@input_id}-label"} class={@theme.listbox}>
        <li :if={@suggestions_loading} role="presentation" class={@theme.loading_state}>
          {message(assigns, :loading)}
        </li>
        <li
          :if={!@suggestions_loading && @suggestions == [] && @value_hint}
          role="presentation"
          class={@theme.hint}
        >
          {@value_hint}
        </li>
        <li
          :if={!@suggestions_loading && @suggestions == [] && !@value_hint}
          role="presentation"
          class={@theme.empty_state}
        >
          {message(assigns, :no_results)}
        </li>
        <li
          :for={{suggestion, index} <- Enum.with_index(@suggestions)}
          :if={!@suggestions_loading}
          role="presentation"
        >
          <button
            id={suggestion_id(assigns, index)}
            type="button"
            role="option"
            aria-selected="false"
            tabindex="-1"
            class={[@theme.option, suggestion_count(assigns, suggestion) == 0 && @theme.facet_count_zero]}
            style="display:block;width:100%;text-align:left"
            aria-label={suggestion_aria_label(assigns, suggestion)}
            phx-click="select_suggestion"
            phx-value-insert={suggestion.meta.insert}
            phx-target={@myself}
            disabled={!@connected?}
          >
            <%!-- Spec 021: the count is part of the option's accessible name,
            not a sibling node a screen reader would read adrift from its
            label — "Active, 12 results", one string. A zero-count value stays
            visible and selectable, dimmed: hiding it answers "why did that
            option vanish?" with silence, where `0` answers it. --%>
            <span>{suggestion.label}</span>
            <span :if={suggestion.sublabel}>{suggestion.sublabel}</span>
            <span :if={suggestion_count(assigns, suggestion)} class={@theme.facet_count}>
              {suggestion_count(assigns, suggestion)}
            </span>
          </button>
        </li>
      </ul>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".FlickerSearchNav">
        // Keyboard nav over the suggestion list — the same shape as
        // `Flicker.Components.Select`'s `.Nav` hook (arrow keys move a
        // highlighted index, Enter clicks it, Escape closes) but scoped to
        // this component's own suggestion `<ul>`, since `Flicker.search`
        // has no selection/multi-select behaviour to also handle.
        // Shares its guard flag and event name with
        // `Flicker.Components.Select`'s `.Nav` hook — deliberately, since
        // `Flicker.search/1` and `Flicker.select/1` can both be mounted on
        // the same page (Spec 005's dev playground layout puts a
        // `Flicker.search/1` in the shared chrome above every page's own
        // content) and only the *first* hook to mount would otherwise win
        // the registration, silently leaving the other's `push_event`s
        // handled by a stale/mismatched listener. Both components'
        // versions of this block must stay identical (value-aware) so it
        // genuinely doesn't matter which one wins (caught by Spec 007's
        // browser suite: a real page with both mounted showed the
        // `Flicker.select/1` half of this working, or the `Flicker.search/1`
        // half, but never both, depending on mount order).
        if (!window.__flickerFocusListenerAttached) {
          window.__flickerFocusListenerAttached = true
          window.addEventListener("phx:focusElementById", e => {
            const el = document.getElementById(e.detail.id)
            if (!el) return
            if (e.detail.value !== undefined) el.value = e.detail.value
            el.focus()
          })
        }

        export default {
          mounted() {
            this.activeIndex = -1
            this.onKeydown = e => this.handleKeydown(e)
            this.el.addEventListener("keydown", this.onKeydown)
            this.attachCursorReporting()
          },
          updated() {
            this.activeIndex = -1
            this.render()
            this.attachCursorReporting()
          },
          destroyed() {
            this.el.removeEventListener("keydown", this.onKeydown)
            this.detachCursorReporting()
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
          // immediately.
          // Idempotent, and safe to call again from `updated()`: the input
          // node itself gets replaced as suggestions/results re-render (not
          // just patched in place), which would silently drop a listener
          // bound directly to it — re-attaching only when the node actually
          // changed keeps this cheap on the common case (same node) while
          // never leaving cursor reporting dangling after a re-render.
          attachCursorReporting() {
            const input = this.inputEl()
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
          inputEl() {
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
            const next = this.activeIndex + delta
            this.activeIndex = Math.max(0, Math.min(options.length - 1, next))
            this.render()
          },
          handleKeydown(e) {
            const options = this.options()
            const isOpen = this.el.querySelector('[role="listbox"]') !== null
            switch (e.key) {
              case "ArrowDown":
                if (isOpen) {
                  e.preventDefault()
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
                if (isOpen && this.activeIndex >= 0 && options[this.activeIndex]) {
                  e.preventDefault()
                  options[this.activeIndex].click()
                } else if (this.el.dataset.dispatch === "enter") {
                  // Spec 020's `:enter` policy: no suggestion under the
                  // keyboard cursor means Enter is asking for the search to
                  // run. Choosing a suggestion always wins when there is one.
                  e.preventDefault()
                  this.pushEventTo(this.el, "dispatch_query", {})
                }
                break
              case "Escape":
                this.pushEventTo(this.el, "close", {})
                break
              case "Backspace":
                // Empty input + Backspace removes the last committed facet
                // pill (Spec 012), mirroring multi-select's chip behaviour;
                // with text present it's an ordinary edit, left alone.
                if (this.inputEl()?.value === "") this.pushEventTo(this.el, "remove_last_facet", {})
                break
              default:
                break
            }
          },
          render() {
            const activeClass = this.activeClass()
            // Class *lists*, split before toggling — same fix, same
            // reasoning, as `Flicker.Components.Select`'s `.Nav` render().
            const activeClasses = activeClass ? activeClass.split(/\s+/).filter(Boolean) : []
            this.options().forEach((option, i) => {
              const active = i === this.activeIndex
              option.setAttribute("aria-selected", active ? "true" : "false")
              activeClasses.forEach(cls => option.classList.toggle(cls, active))
            })
          }
        }
      </script>
    </div>
    """
  end
end
