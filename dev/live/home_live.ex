defmodule Dev.Live.Home do
  @moduledoc """
  The dev playground's landing page (Spec 005) — links to every capability
  page, each backed by the seeded `Dev.Music` domain or a pure-Elixir
  provider.
  """

  use Phoenix.LiveView

  @pages [
    {"/single-select", "Single select",
     "Form mode + controlled mode side by side, actor toggle on the policy-bearing resource"},
    {"/multi-select", "Multi-select", "Chips, batch fetch/2 on a preselected edit form, and a max_selections cap"},
    {"/static-provider", "Static provider", "Pure-Elixir, no-Ash `Flicker.Providers.Static` path"},
    {"/themes", "Theme showcase", "The same select in every shipped theme preset"},
    {"/edge-states", "Edge states", "Slow, erroring, and empty-result providers, on demand"},
    {"/keyboard-activation", "Keyboard activation",
     "mod+k focuses and opens a search from anywhere on the page, plus the duplicate-chord warning"},
    {"/faceted-search", "Faceted search",
     "Flicker.search filtering a live list of Dev.Music artists — key/value facet autocomplete, no selection semantics"},
    {"/palette", "Command palette",
     "Flicker.palette federated over the whole Dev.Music domain — grouped Artists/Albums/Genres, mod+k, navigate-on-select"},
    {"/palette-themed", "Command palette — themed",
     "The same palette + federated provider, restyled fullscreen and on-brand via a theme override only"},
    {"/cinder-interop", "Cinder interop",
     "Flicker.search above a Cinder collection of Dev.Music artists — the Level 1 recipe, no adapter code"}
  ]

  @impl true
  @doc "Assigns the page list; no other state."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket), do: {:ok, assign(socket, :pages, @pages)}

  @impl true
  @doc "Renders the page-index nav list."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <h1 class="text-2xl font-semibold">Flicker dev playground</h1>
      <p class="text-sm text-gray-600">
        Every page reads off the seeded `Dev.Music` domain (ETS, no database)
        or a pure-Elixir provider — see
        <a
          class="text-indigo-600 hover:underline"
          href="https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-005-dev-playground.md"
        >
          Spec 005
        </a>.
      </p>
      <ul class="space-y-2">
        <li :for={{path, title, description} <- @pages}>
          <.link navigate={path} class="font-medium text-indigo-600 hover:underline">{title}</.link>
          <span class="text-sm text-gray-600"> — {description}</span>
        </li>
      </ul>
    </div>
    """
  end
end
