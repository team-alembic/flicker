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

  alias Flicker.{CursorContext, FacetSuggest, Messages, Query}

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

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:text, fn -> initial_text || "" end)
      |> assign_new(:cursor, fn -> nil end)
      |> assign_new(:open, fn -> false end)
      |> assign_new(:suggestions_loading, fn -> false end)
      |> assign(:connected?, Phoenix.LiveView.connected?(socket))
      |> refresh_context()

    {:ok, socket}
  end

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
    socket =
      socket
      |> assign(
        text: text,
        cursor: CursorContext.parse_selection_start(params["cursor"]),
        open: true
      )
      |> refresh_context()
      |> notify_change()

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
      |> refresh_context()
      |> notify_change()

    {:noreply, focus_input(socket, new_text)}
  end

  def handle_event("focus", _params, socket), do: {:noreply, assign(socket, open: true)}

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, open: false)}

  def handle_event("clear", _params, socket) do
    socket =
      socket
      |> assign(text: "", cursor: nil, open: false)
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

  defp notify_change(socket) do
    facets = socket.assigns.facets
    query = Query.parse(socket.assigns.text, facets)
    filter = to_filter(query, facets)

    send(self(), {socket.assigns.on_change, query, filter})
    socket
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
      |> assign(:show_suggestions, assigns.open and assigns.context != :text)

    assigns = assign(assigns, :announcement, announcement(assigns))

    ~H"""
    <div
      id={@id}
      class={@theme.wrapper}
      phx-hook=".FlickerSearchNav"
      phx-target={@myself}
      phx-click-away="close"
      data-active-class={@theme.option_active}
    >
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
        class={@theme.search_input}
        value={@text}
        placeholder={message(assigns, :facet_search_placeholder)}
        disabled={!@connected?}
        phx-keyup="query"
        phx-debounce={@debounce}
        phx-focus="focus"
        phx-target={@myself}
      />
      <button
        :if={@text != ""}
        type="button"
        class={@theme.clear_button}
        disabled={!@connected?}
        phx-click="clear"
        phx-target={@myself}
        aria-label={message(assigns, :clear_selection)}
      >
        {message(assigns, :clear_selection)}
      </button>
      <div id={"#{@id}-announcer"} aria-live="polite" class="flicker-sr-only" style={@sr_only_style}>
        {@announcement}
      </div>
      <ul :if={@show_suggestions} id={@listbox_id} role="listbox" aria-labelledby={"#{@input_id}-label"} class={@theme.listbox}>
        <li :if={@suggestions_loading} class={@theme.loading_state}>{message(assigns, :loading)}</li>
        <li :if={!@suggestions_loading && @suggestions == []} class={@theme.empty_state}>
          {message(assigns, :no_results)}
        </li>
        <li
          :for={{suggestion, index} <- Enum.with_index(@suggestions)}
          :if={!@suggestions_loading}
          id={suggestion_id(assigns, index)}
          role="option"
          aria-selected="false"
          class={@theme.option}
        >
          <button
            type="button"
            tabindex="-1"
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
                  options[this.activeIndex].querySelector("button")?.click()
                }
                break
              case "Escape":
                this.pushEventTo(this.el, "close", {})
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
              const button = option.querySelector("button")
              if (button) activeClasses.forEach(cls => button.classList.toggle(cls, active))
            })
          }
        }
      </script>
    </div>
    """
  end
end
