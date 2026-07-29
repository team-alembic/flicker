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

  alias Flicker.{CursorContext, Dispatch, FacetSuggest, Messages, Query}

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

  def handle_event("select_suggestion", %{"insert" => insert}, socket) do
    new_text =
      FacetSuggest.replace_current_token(socket.assigns.text, insert, socket.assigns.cursor)

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
    suggestions = FacetSuggest.enum_value_suggestions(facet, prefix)

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
  defp notify_change(socket, trigger \\ :facet_commit) do
    facets = socket.assigns.facets

    if Dispatch.dispatch?(socket.assigns.dispatch, trigger, socket.assigns.text, 0) do
      query = combined_query(socket, facets)
      filter = to_filter(query, facets)

      send(self(), {socket.assigns.on_change, query, filter})
      assign(socket, :dispatched_text, socket.assigns.text)
    else
      socket
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

  defp op_prefix(:neq), do: "≠ "
  defp op_prefix(:gt), do: "> "
  defp op_prefix(:gte), do: "≥ "
  defp op_prefix(:lt), do: "< "
  defp op_prefix(:lte), do: "≤ "
  defp op_prefix(_eq_or_contains), do: ""

  defp value_display(%{value_labels: labels}, value) when is_map(labels) and is_atom(value),
    do: Map.get(labels, value) || humanize(to_string(value))

  defp value_display(_facet, %Date{} = date), do: Date.to_iso8601(date)
  defp value_display(_facet, value) when is_atom(value), do: humanize(to_string(value))
  defp value_display(_facet, value), do: to_string(value)

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
          aria-describedby={@dispatch_pending && "#{@input_id}-dispatch-hint"}
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
            class={@theme.option}
            style="display:block;width:100%;text-align:left"
            phx-click="select_suggestion"
            phx-value-insert={suggestion.meta.insert}
            phx-target={@myself}
            disabled={!@connected?}
          >
            <span>{suggestion.label}</span> <span :if={suggestion.sublabel}>{suggestion.sublabel}</span>
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
