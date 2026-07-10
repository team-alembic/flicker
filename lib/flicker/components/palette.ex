defmodule Flicker.Components.Palette do
  @moduledoc """
  The internal `Phoenix.LiveComponent` behind `Flicker.palette/1`
  ([Spec 008](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-008-command-palette.md)).

  This module is not part of the public API — hosts never reference it
  directly. `Flicker.palette/1` is the only supported entry point.

  This is deliberately thin: overlay chrome (backdrop, panel, footer,
  focus trap, scroll lock, `Escape`-to-close, and the `mod+k`
  keyboard-activation open/close toggle) plus one nested
  `Flicker.Components.Select` — the exact same core `Flicker.select/1`
  runs — in controlled mode with `navigate_on_select: true`. Nothing here
  duplicates or forks the search behaviour; the seam is entirely at this
  wrapper.

  ## Open/close state

  `open` is host-controlled (`Flicker.palette/1`'s `open` attr) but the
  component also has to open/close itself on the `mod+k` chord and on
  `Escape`/backdrop-click, with no server round trip to the host in
  between. It reconciles the two with a simple edge-detected sync: the
  host's `open` value is adopted whenever it *changes* between renders
  (so a navbar button toggling it always wins), while in between host
  renders the component is free to flip its own `panel_open` in response
  to the chord/`Escape`/backdrop — and always tells the host about it via
  `on_close` so host-side state doesn't drift.
  """

  use Phoenix.LiveComponent

  alias Flicker.Components.Select, as: SelectComponent
  alias Flicker.Messages

  @impl true
  def update(assigns, socket) do
    host_open = !!assigns[:open]

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:panel_open, fn -> host_open end)
      |> assign_new(:prev_host_open, fn -> host_open end)

    socket =
      if host_open == socket.assigns.prev_host_open do
        socket
      else
        assign(socket, panel_open: host_open)
      end

    socket =
      socket
      |> assign(:prev_host_open, host_open)
      |> assign(:connected?, Phoenix.LiveView.connected?(socket))

    {:ok, socket}
  end

  @impl true
  def handle_event("open", _params, socket), do: {:noreply, assign(socket, panel_open: true)}

  def handle_event("close", _params, %{assigns: %{panel_open: false}} = socket), do: {:noreply, socket}

  def handle_event("close", _params, socket) do
    send(self(), socket.assigns.on_close)
    {:noreply, assign(socket, panel_open: false)}
  end

  defp select_theme(theme), do: %{theme | search_input: theme.palette_input}

  defp message(assigns, key, bindings \\ %{}), do: Messages.get(assigns[:messages], key, bindings)

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :select_theme, select_theme(assigns.theme))

    ~H"""
    <div
      id={@id}
      phx-hook=".Palette"
      data-open={to_string(@panel_open)}
      data-activate-with-keyboard={@activate_with_keyboard}
    >
      <div :if={@panel_open} class={@theme.backdrop} phx-click="close" phx-target={@myself}></div>
      <div
        :if={@panel_open}
        id={"#{@id}-panel"}
        role="dialog"
        aria-modal="true"
        aria-label={message(assigns, :palette_label)}
        class={@theme.panel}
      >
        <button
          type="button"
          class={@theme.clear_button}
          phx-click="close"
          phx-target={@myself}
          aria-label={message(assigns, :close_palette)}
        >
          {message(assigns, :close_palette)}
        </button>
        <.live_component
          module={SelectComponent}
          id={"#{@id}-select"}
          provider={@provider}
          field={nil}
          on_select={@on_select}
          navigate_on_select={true}
          actor={@actor}
          tenant={@tenant}
          limit={@limit}
          min_chars={@min_chars}
          debounce={@debounce}
          theme={@select_theme}
          messages={@messages}
          facets={@facets}
          option={@option}
        />
        <div class={@theme.footer}>
          <span><kbd class={@theme.kbd_hint}>↑↓</kbd> {message(assigns, :footer_navigate_hint)}</span>
          <span><kbd class={@theme.kbd_hint}>↵</kbd> {message(assigns, :footer_select_hint)}</span>
          <span><kbd class={@theme.kbd_hint}>esc</kbd> {message(assigns, :footer_close_hint)}</span>
        </div>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Palette">
        // Overlay chrome (Spec 008): the `mod+k` open/close toggle (shares
        // `window.__flickerChordRegistry`/the one document listener with
        // `Flicker.Components.Select`'s `.Nav` hook — duplicated here, not
        // imported, because colocated hooks are standalone modules), focus
        // trap, focus restore on close, scroll lock, and `Escape`-to-close
        // (after the Spec 001 two-stage escape inside the nested search
        // input has had first refusal).
        function flickerPaletteIsMac() {
          const platform = navigator.userAgentData?.platform || navigator.platform || ""
          return /Mac|iPhone|iPad/.test(platform)
        }

        function flickerPaletteResolveModifier(modifier) {
          return modifier === "mod" ? (flickerPaletteIsMac() ? "meta" : "ctrl") : modifier
        }

        function flickerPaletteChordSignature(modifiers, key) {
          return `${Array.from(new Set(modifiers)).sort().join("+")}+${key.toLowerCase()}`
        }

        function flickerPaletteParseChordSignature(chord) {
          const parts = chord.split("+")
          const key = parts[parts.length - 1]
          const modifiers = parts.slice(0, -1).map(flickerPaletteResolveModifier)
          return flickerPaletteChordSignature(modifiers, key)
        }

        function flickerPaletteEventSignature(e) {
          const modifiers = []
          if (e.metaKey) modifiers.push("meta")
          if (e.ctrlKey) modifiers.push("ctrl")
          if (e.altKey) modifiers.push("alt")
          if (e.shiftKey) modifiers.push("shift")
          return flickerPaletteChordSignature(modifiers, e.key)
        }

        if (!window.__flickerChordRegistry) window.__flickerChordRegistry = new Map()

        if (!window.__flickerActivationListenerAttached) {
          window.__flickerActivationListenerAttached = true
          document.addEventListener("keydown", e => {
            const hook = window.__flickerChordRegistry.get(flickerPaletteEventSignature(e))
            hook?.activateChord(e)
          })
        }

        export default {
          mounted() {
            this.wasOpen = this.el.dataset.open === "true"
            this.previouslyFocused = null
            this.chordSignature = null
            this.onKeydown = e => this.handleKeydown(e)
            this.el.addEventListener("keydown", this.onKeydown)
            const chord = this.el.dataset.activateWithKeyboard
            if (chord) this.registerChord(chord)
            if (this.wasOpen) this.onOpen()
          },
          updated() {
            const isOpen = this.el.dataset.open === "true"
            if (isOpen && !this.wasOpen) this.onOpen()
            if (!isOpen && this.wasOpen) this.onClose()
            this.wasOpen = isOpen
          },
          destroyed() {
            this.el.removeEventListener("keydown", this.onKeydown)
            if (this.wasOpen) this.onClose()
            if (this.chordSignature && window.__flickerChordRegistry.get(this.chordSignature) === this) {
              window.__flickerChordRegistry.delete(this.chordSignature)
            }
          },
          registerChord(chord) {
            const signature = flickerPaletteParseChordSignature(chord)
            if (window.__flickerChordRegistry.has(signature)) {
              console.warn(
                `Flicker: activate_with_keyboard chord "${chord}" is already claimed by another ` +
                  "component on this page — the first registration wins, this one is inactive."
              )
              return
            }
            window.__flickerChordRegistry.set(signature, this)
            this.chordSignature = signature
          },
          activateChord(e) {
            e.preventDefault()
            if (this.el.dataset.open === "true") {
              this.pushEventTo(this.el, "close", {})
            } else {
              this.pushEventTo(this.el, "open", {})
            }
          },
          onOpen() {
            this.previouslyFocused = document.activeElement
            document.body.style.overflow = "hidden"
            this.panelInput()?.focus()
          },
          onClose() {
            document.body.style.overflow = ""
            if (this.previouslyFocused && document.contains(this.previouslyFocused)) {
              this.previouslyFocused.focus()
            }
            this.previouslyFocused = null
          },
          panel() {
            return this.el.querySelector('[role="dialog"]')
          },
          panelInput() {
            return this.el.querySelector('input[type="text"]')
          },
          focusable() {
            const panel = this.panel()
            if (!panel) return []
            return Array.from(
              panel.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])')
            ).filter(el => !el.disabled)
          },
          handleKeydown(e) {
            if (this.el.dataset.open !== "true") return
            if (e.key === "Escape") {
              const input = this.panelInput()
              const listboxOpen = this.el.querySelector('[role="listbox"]') !== null
              const hasText = !!input && input.value !== ""
              if (!hasText && !listboxOpen) {
                e.stopPropagation()
                this.pushEventTo(this.el, "close", {})
              }
              return
            }
            if (e.key === "Tab") this.trapFocus(e)
          },
          trapFocus(e) {
            const focusable = this.focusable()
            if (focusable.length === 0) return
            const first = focusable[0]
            const last = focusable[focusable.length - 1]
            if (e.shiftKey && document.activeElement === first) {
              e.preventDefault()
              last.focus()
            } else if (!e.shiftKey && document.activeElement === last) {
              e.preventDefault()
              first.focus()
            }
          }
        }
      </script>
    </div>
    """
  end
end
