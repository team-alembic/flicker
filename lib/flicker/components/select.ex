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
  """

  use Phoenix.LiveComponent

  alias Flicker.{Messages, Provider, Query, Result}

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
      {:noreply, apply_query(socket, text)}
    end
  end

  def handle_event("select", %{"value" => raw_value}, %{assigns: %{multiple: true}} = socket) do
    result = Enum.find(socket.assigns.results, &(to_string(&1.value) == raw_value))

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

  def handle_event("select", %{"value" => raw_value}, socket) do
    result = Enum.find(socket.assigns.results, &(to_string(&1.value) == raw_value))

    socket =
      socket
      |> assign(selected: result, query: display_text(result), open: false)
      |> notify_selection(result)

    {:noreply, socket}
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

  def handle_async(:search, {:exit, reason}, socket) do
    Logger.warning("Flicker search task exited: #{inspect(reason)}")
    {:noreply, assign(socket, results: [], has_more: false, loading: false, error: true)}
  end

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
  defp run_search(socket, text) do
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
      |> assign(:sr_only_style, @sr_only_style)

    ~H"""
    <div
      id={@id}
      class={@theme.wrapper}
      phx-hook=".Nav"
      phx-target={@myself}
      phx-click-away="close"
      data-active-class={@theme.option_active}
      data-multiple={to_string(@multiple)}
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
      <label for={@input_id} class="flicker-sr-only" style={@sr_only_style}>{message(assigns, :search_placeholder)}</label>
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
        phx-keyup="query"
        phx-debounce={@debounce}
        phx-focus="focus"
        phx-target={@myself}
      />
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
      <div aria-live="polite" class="flicker-sr-only" style={@sr_only_style}>
        {message(assigns, :results_count, %{count: length(@results)})}
      </div>
      <div :if={@multiple} aria-live="polite" class="flicker-sr-only" style={@sr_only_style}>
        {message(assigns, :selected_count, %{count: length(@selected)})}
      </div>
      <ul :if={@open} id={@listbox_id} role="listbox" class={@theme.listbox}>
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
          <li
            :for={{result, index} <- Enum.with_index(@results)}
            id={option_id(assigns, index)}
            role="option"
            aria-selected="false"
            class={@theme.option}
          >
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
            this.input()?.focus()
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
