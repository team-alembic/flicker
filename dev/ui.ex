defmodule Dev.UI do
  @moduledoc """
  Shared chrome for the dev playground (Spec 005) — the sidebar shell,
  page-header pattern, and card-section wrapper every capability page
  composes with. Kept deliberately thin: playground `Dev.Live.*` modules
  should read like the README/guide examples they double as, so the chrome
  lives here instead of being repeated inline on every page.

  Restyles *around* `Flicker`/`Cinder` component instances only — nothing
  here touches a component's `id`, attrs, or ARIA structure, since the
  browser-driven suite (Spec 007) asserts against those directly.
  """

  use Phoenix.Component

  @nav_groups [
    {"Selection",
     [
       {"/single-select", "Single select"},
       {"/multi-select", "Multi-select"},
       {"/keyboard-activation", "Keyboard activation"}
     ]},
    {"Search", [{"/faceted-search", "Faceted search"}, {"/windowed-search", "Windowed search"}]},
    {"Palette", [{"/palette", "Palette"}, {"/palette-themed", "Palette — themed"}]},
    {"Providers & edge cases", [{"/static-provider", "Static provider"}, {"/edge-states", "Edge states"}]},
    {"Theming", [{"/themes", "Themes"}]},
    {"Integration", [{"/cinder-interop", "Cinder interop"}]}
  ]

  @doc "The playground's fixed nav groups, exposed for the home page's capability grid."
  @spec nav_groups() :: [{String.t(), [{String.t(), String.t()}]}]
  def nav_groups, do: @nav_groups

  @doc """
  Wraps a capability page: fixed left sidebar on desktop (an off-canvas
  drawer on mobile, toggled by a hidden checkbox — no client JS needed), a
  page-header (`title`, one-line `description` slot, optional `spec` link),
  and the page's own content underneath.

  `current_path` drives the sidebar's active-page state — passed explicitly
  by each page rather than introspected, since the root layout's shell
  never re-renders across `live_navigate` (only each LiveView's own
  template does).
  """
  attr(:title, :string, required: true)
  attr(:current_path, :string, required: true)

  attr(:spec, :string,
    default: nil,
    doc: "path under the repo root, e.g. \"docs/specs/spec-001-....md\""
  )

  slot(:description, required: false)
  slot(:inner_block, required: true)

  @spec page(map()) :: Phoenix.LiveView.Rendered.t()
  def page(assigns) do
    ~H"""
    <div class="mx-auto flex min-h-screen max-w-7xl items-start">
      <input type="checkbox" id="dev-nav-toggle" class="peer hidden" />
      <label
        for="dev-nav-toggle"
        class="fixed inset-0 z-30 hidden bg-gray-900/30 peer-checked:block lg:hidden"
        aria-hidden="true"
      >
      </label>
      <.sidebar current_path={@current_path} />

      <div class="min-w-0 flex-1">
        <header class="flex items-center justify-between border-b border-gray-200 px-6 py-4 lg:hidden">
          <label
            for="dev-nav-toggle"
            class="cursor-pointer rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700"
          >
            ☰ Menu
          </label>
          <span class="text-sm font-semibold text-gray-900">🔥 Flicker</span>
        </header>

        <main class="mx-auto max-w-4xl px-6 py-10">
          <div class="mb-8 space-y-2 border-b border-gray-200 pb-6">
            <h1 class="text-2xl font-semibold tracking-tight text-gray-900">{@title}</h1>
            <p :if={@description != []} class="text-sm leading-relaxed text-gray-600">
              {render_slot(@description)}
            </p>
            <a
              :if={@spec}
              href={"https://github.com/team-alembic/flicker/blob/main/" <> @spec}
              class="inline-flex items-center gap-1 text-xs font-medium text-indigo-600 hover:text-indigo-500"
            >
              View spec on GitHub →
            </a>
          </div>

          <div class="space-y-8">
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>
    """
  end

  attr(:current_path, :string, required: true)

  defp sidebar(assigns) do
    assigns = assign(assigns, :nav_groups, @nav_groups)

    ~H"""
    <aside class="fixed inset-y-0 left-0 z-40 hidden w-64 flex-col overflow-y-auto border-r border-gray-200 bg-white peer-checked:flex lg:flex">
      <div class="flex items-center justify-between border-b border-gray-200 px-4 py-4">
        <.link navigate="/" class="flex items-center gap-1.5 text-base font-semibold text-gray-900">
          <span aria-hidden="true">🔥</span> Flicker
        </.link>
        <a
          href="https://github.com/team-alembic/flicker"
          class="text-gray-600 hover:text-gray-900"
          aria-label="Flicker on GitHub"
        >
          <span aria-hidden="true">GitHub</span>
        </a>
      </div>

      <nav class="flex-1 space-y-5 px-3 py-4">
        <.nav_link path="/" title="Home" current_path={@current_path} />

        <div :for={{group, links} <- @nav_groups}>
          <p class="mb-1 px-3 text-xs font-semibold uppercase tracking-wide text-gray-600">{group}</p>
          <div class="space-y-0.5">
            <.nav_link :for={{path, title} <- links} path={path} title={title} current_path={@current_path} />
          </div>
        </div>
      </nav>
    </aside>
    """
  end

  attr(:path, :string, required: true)
  attr(:title, :string, required: true)
  attr(:current_path, :string, required: true)

  defp nav_link(assigns) do
    assigns = assign(assigns, :active?, assigns.path == assigns.current_path)

    ~H"""
    <.link
      navigate={@path}
      aria-current={@active? && "page"}
      class={[
        "block rounded-md px-3 py-1.5 text-sm",
        @active? && "bg-indigo-50 font-medium text-indigo-700",
        !@active? && "text-gray-600 hover:bg-gray-50 hover:text-gray-900"
      ]}
    >
      {@title}
    </.link>
    """
  end

  @doc """
  A bordered card with a small uppercase label — the demo-section pattern
  every capability page's individual examples sit inside.
  """
  attr(:label, :string, required: true)
  attr(:class, :string, default: nil)
  slot(:inner_block, required: true)

  @spec section(map()) :: Phoenix.LiveView.Rendered.t()
  def section(assigns) do
    ~H"""
    <section class={["rounded-lg border border-gray-200 bg-white p-6", @class]}>
      <p class="mb-4 text-xs font-semibold uppercase tracking-wide text-gray-500">{@label}</p>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  The repeated "acting as" actor-switch fieldset (Spec 005's policy-bearing
  resource demo) — used wherever a page toggles `Dev.Music.Artist`'s
  visible-labels actor.
  """
  attr(:actors, :list, required: true, doc: "[{display_name, label_or_nil}]")
  attr(:selected, :any, required: true)
  attr(:event, :string, default: "set_actor")

  @spec actor_toggle(map()) :: Phoenix.LiveView.Rendered.t()
  def actor_toggle(assigns) do
    ~H"""
    <fieldset class="flex flex-wrap items-center gap-2">
      <legend class="mb-1 text-sm font-medium text-gray-700">Acting as</legend>
      <button
        :for={{name, label} <- @actors}
        type="button"
        phx-click={@event}
        phx-value-label={label || ""}
        class={[
          "rounded-md px-3 py-1 text-sm transition-colors",
          if(@selected == label, do: "bg-indigo-600 text-white", else: "bg-gray-100 text-gray-700 hover:bg-gray-200")
        ]}
      >
        {name}
      </button>
    </fieldset>
    """
  end

  @doc """
  Wraps a live example with its source in a copy-to-clipboard code block
  (Spec 014) — the component-library "here's the component, here's the code"
  pattern. `code` is the source shown (kept next to the live example so the
  two stay in sync); the `inner_block` is the live render.
  """
  attr(:id, :string, required: true)
  attr(:code, :string, required: true)

  attr(:lang, :string,
    default: "heex",
    doc: "\"heex\" syntax-highlights; anything else renders plain."
  )

  slot(:inner_block, required: true)

  @spec code_example(map()) :: Phoenix.LiveView.Rendered.t()
  def code_example(assigns) do
    assigns = assign(assigns, :rendered_code, render_code(assigns.code, assigns.lang))

    ~H"""
    <div>
      {render_slot(@inner_block)}
      <div class="relative mt-3 overflow-hidden rounded-md bg-gray-900">
        <button
          id={@id}
          phx-hook=".CopyCode"
          data-code={@code}
          type="button"
          class="absolute right-2 top-2 rounded border border-gray-600 bg-gray-800 px-2 py-1 text-xs font-medium text-gray-200 hover:bg-gray-700"
        >
          Copy
        </button>
        <pre tabindex="0" class="overflow-x-auto p-4 text-xs leading-relaxed text-gray-100"><code>{@rendered_code}</code></pre>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyCode">
        export default {
          mounted() {
            this.onClick = () => {
              navigator.clipboard.writeText(this.el.dataset.code).then(() => {
                const original = this.el.textContent
                this.el.textContent = "Copied"
                setTimeout(() => { this.el.textContent = original }, 1500)
              })
            }
            this.el.addEventListener("click", this.onClick)
          },
          destroyed() {
            this.el.removeEventListener("click", this.onClick)
          }
        }
      </script>
    </div>
    """
  end

  # A small, dependency-free HEEx syntax highlighter for the playground's code
  # blocks (Spec 014). Makeup ships only Elixir/Erlang lexers, which mangle
  # component markup, so this does a single alternation pass and wraps each
  # recognised token in an inline-coloured span (inline styles keep it
  # self-contained — the playground ships no syntax-highlight stylesheet).
  # Deliberately approximate: good enough to read, never executed.
  @heex_token ~r/(<%!--.*?--%>|"[^"]*"|\{[^{}]*\}|<\/?[A-Za-z][\w.]*|[A-Za-z_][\w-]*(?==)|:[a-z][\w?]*)/s

  @heex_colors %{
    tag: "#7ee787",
    attr: "#79c0ff",
    string: "#a5d6ff",
    expr: "#d2a8ff",
    atom: "#ffa657",
    comment: "#8b949e"
  }

  defp render_code(code, "heex"), do: highlight_heex(code)
  defp render_code(code, _lang), do: Phoenix.HTML.raw(escape_code(code))

  @spec highlight_heex(String.t()) :: Phoenix.HTML.safe()
  def highlight_heex(code) do
    @heex_token
    |> Regex.split(code, include_captures: true, trim: false)
    |> Enum.map_join("", &highlight_piece/1)
    |> Phoenix.HTML.raw()
  end

  defp highlight_piece(piece) do
    case token_type(piece) do
      nil -> escape_code(piece)
      type -> ~s(<span style="color:#{@heex_colors[type]}">#{escape_code(piece)}</span>)
    end
  end

  defp token_type(piece) do
    cond do
      piece == "" -> nil
      String.starts_with?(piece, "<%!--") -> :comment
      String.starts_with?(piece, "\"") -> :string
      String.starts_with?(piece, "{") -> :expr
      String.match?(piece, ~r/^<\/?[A-Za-z]/) -> :tag
      String.starts_with?(piece, ":") -> :atom
      String.match?(piece, ~r/^[A-Za-z_][\w-]*$/) -> :attr
      true -> nil
    end
  end

  defp escape_code(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  @doc "One linked card in the home page's capability grid."
  attr(:path, :string, required: true)
  attr(:title, :string, required: true)
  attr(:description, :string, required: true)

  @spec capability_card(map()) :: Phoenix.LiveView.Rendered.t()
  def capability_card(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class="block rounded-lg border border-gray-200 bg-white p-5 transition-colors hover:border-indigo-300 hover:bg-indigo-50/40"
    >
      <p class="font-medium text-gray-900">{@title}</p>
      <p class="mt-1 text-sm text-gray-600">{@description}</p>
    </.link>
    """
  end
end
