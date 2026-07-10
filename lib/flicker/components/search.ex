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
  """

  use Phoenix.LiveComponent

  alias Flicker.{FacetSuggest, Messages, Query}

  require Logger

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:text, fn -> "" end)
      |> assign_new(:open, fn -> false end)
      |> assign_new(:suggestions_loading, fn -> false end)
      |> assign(:connected?, Phoenix.LiveView.connected?(socket))
      |> refresh_context()

    {:ok, socket}
  end

  @impl true
  def handle_event("query", %{"value" => text}, socket) do
    socket =
      socket
      |> assign(text: text, open: true)
      |> refresh_context()
      |> notify_change()

    {:noreply, socket}
  end

  def handle_event("select_suggestion", %{"insert" => insert}, socket) do
    new_text = FacetSuggest.replace_current_token(socket.assigns.text, insert)

    socket =
      socket
      |> assign(text: new_text, open: true)
      |> refresh_context()
      |> notify_change()

    {:noreply, push_event(socket, "focusElementById", %{id: input_id(socket)})}
  end

  def handle_event("focus", _params, socket), do: {:noreply, assign(socket, open: true)}

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, open: false)}

  def handle_event("clear", _params, socket) do
    socket =
      socket
      |> assign(text: "", open: false)
      |> refresh_context()
      |> notify_change()

    {:noreply, push_event(socket, "focusElementById", %{id: input_id(socket)})}
  end

  @impl true
  def handle_async(:related_search, {:ok, {:ok, suggestions}}, socket) do
    {:noreply, assign(socket, suggestions: suggestions, suggestions_loading: false)}
  end

  def handle_async(:related_search, {:ok, {:error, reason}}, socket) do
    Logger.warning("Flicker facet related search failed: #{inspect(reason)}")
    {:noreply, assign(socket, suggestions: [], suggestions_loading: false)}
  end

  def handle_async(:related_search, {:exit, reason}, socket) do
    Logger.warning("Flicker facet related search task exited: #{inspect(reason)}")
    {:noreply, assign(socket, suggestions: [], suggestions_loading: false)}
  end

  defp refresh_context(socket) do
    facets = socket.assigns.facets
    context = FacetSuggest.classify(socket.assigns.text, facets)

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
    filter = if Code.ensure_loaded?(Ash), do: Query.to_filter(query, facets)

    send(self(), {socket.assigns.on_change, query, filter})
    socket
  end

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
        if (!window.__flickerFocusListenerAttached) {
          window.__flickerFocusListenerAttached = true
          window.addEventListener("phx:focusElementById", e => {
            document.getElementById(e.detail.id)?.focus()
          })
        }

        export default {
          mounted() {
            this.activeIndex = -1
            this.onKeydown = e => this.handleKeydown(e)
            this.el.addEventListener("keydown", this.onKeydown)
          },
          updated() {
            this.activeIndex = -1
            this.render()
          },
          destroyed() {
            this.el.removeEventListener("keydown", this.onKeydown)
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
            this.options().forEach((option, i) => {
              const active = i === this.activeIndex
              option.setAttribute("aria-selected", active ? "true" : "false")
              const button = option.querySelector("button")
              if (button && activeClass) button.classList.toggle(activeClass, active)
            })
          }
        }
      </script>
    </div>
    """
  end
end
