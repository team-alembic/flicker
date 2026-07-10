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
      |> assign_new(:selected, fn -> nil end)
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
        socket
        |> assign(open: true, query: "")
        |> run_search("")
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

  def handle_event("select", %{"value" => raw_value}, socket) do
    result = Enum.find(socket.assigns.results, &(to_string(&1.value) == raw_value))

    socket =
      socket
      |> assign(selected: result, query: display_text(result), open: false)
      |> notify_selection(result)

    {:noreply, socket}
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

    {:noreply,
     assign(socket,
       results: Enum.take(results, limit),
       has_more: length(results) > limit,
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
        assign(socket, results: [], has_more: false, loading: false, error: false)

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

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:input_id, input_id_for(assigns.id))
      |> assign(:listbox_id, listbox_id_for(assigns.id))

    ~H"""
    <div id={@id} class={@theme.wrapper} phx-hook=".Nav" phx-target={@myself} data-active-class={@theme.option_active}>
      <label for={@input_id} class="flicker-sr-only">{message(assigns, :search_placeholder)}</label>
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
      <div aria-live="polite" class="flicker-sr-only">
        {message(assigns, :results_count, %{count: length(@results)})}
      </div>
      <ul :if={@open} id={@listbox_id} role="listbox" class={@theme.listbox}>
        <li :if={@loading} class={@theme.loading_state}>{message(assigns, :loading)}</li>
        <li :if={@error} class={@theme.error_state}>{message(assigns, :error)}</li>
        <li :if={!@loading && !@error && @results == []} class={@theme.empty_state}>
          {message(assigns, :no_results)}
        </li>
        <li :for={{result, index} <- Enum.with_index(@results)} id={option_id(assigns, index)} role="option" aria-selected="false" class={@theme.option}>
          <button type="button" phx-click="select" phx-value-value={to_string(result.value)} phx-target={@myself} disabled={!@connected?}>
            <%= if @option != [] do %>
              {render_slot(@option, result)}
            <% else %>
              <span>{result.label}</span> <span :if={result.sublabel}>{result.sublabel}</span>
            <% end %>
          </button>
        </li>
        <li :if={@has_more} class={@theme.hint}>{message(assigns, :keep_typing)}</li>
      </ul>
      <%= if @field do %>
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
            // none after results update).
            this.activeIndex = -1
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
                  this.pushEventTo(this.el, "focus", {})
                  this.activeIndex = 0
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
