defmodule Dev.Live.Home do
  @moduledoc """
  The dev playground's landing page (Spec 005) — what Flicker is, in one
  paragraph, then a grid of capability cards linking to every page, each
  backed by the seeded `Dev.Music` domain or a pure-Elixir provider.
  """

  use Phoenix.LiveView

  import Dev.UI

  @pages [
    {"/single-select", "Single select",
     "Form mode + controlled mode side by side, actor toggle on the policy-bearing resource"},
    {"/multi-select", "Multi-select", "Chips, batch fetch/2 on a preselected edit form, and a max_selections cap"},
    {"/keyboard-activation", "Keyboard activation",
     "mod+k focuses and opens a search from anywhere on the page, plus the duplicate-chord warning"},
    {"/faceted-search", "Faceted search",
     "Flicker.search filtering a live list of Dev.Music artists — key/value facet autocomplete, no selection semantics"},
    {"/windowed-search", "Windowed search",
     "paginate infinite scroll over a 220-artist AshResource population and a 150-row slow provider"},
    {"/palette", "Command palette",
     "Flicker.palette federated over the whole Dev.Music domain — grouped Artists/Albums/Genres, mod+k, navigate-on-select"},
    {"/palette-themed", "Command palette — themed",
     "The same palette + federated provider, restyled fullscreen and on-brand via a theme override only"},
    {"/static-provider", "Static provider", "Pure-Elixir, no-Ash Flicker.Providers.Static path"},
    {"/edge-states", "Edge states", "Slow, erroring, and empty-result providers, on demand"},
    {"/themes", "Theme showcase", "The same select in every shipped theme preset"},
    {"/cinder-interop", "Cinder interop",
     "Flicker.search above a Cinder collection of Dev.Music artists — the Level 1 recipe, no adapter code"}
  ]

  @impl true
  @doc "Assigns the capability-card list; no other state."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket), do: {:ok, assign(socket, :pages, @pages)}

  @impl true
  @doc "Renders the landing page: what Flicker is, then the capability grid."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.page title="Flicker dev playground" current_path="/">
      <:description>
        Manually exercise every Flicker capability against seeded data —
        see
        <a
          class="text-indigo-600 underline"
          href="https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-005-dev-playground.md"
        >
          Spec 005
        </a>.
      </:description>

      <.section label="What is Flicker">
        <p class="text-sm leading-relaxed text-gray-700">
          <strong>Flicker</strong>
          is an Ash-native searchable select / combobox / faceted-search
          component for Phoenix LiveView — what
          <a href="https://github.com/team-alembic/cinder" class="text-indigo-600 underline">Cinder</a>
          is for tables, Flicker is for searching, filtering, and selecting
          records. It reads directly off Ash resources (no options
          plumbing), authorises via <code>actor:</code>
          + policies, derives facet behaviour from the Ash type system, and
          installs via Igniter. Every page below reads off the seeded
          <code>Dev.Music</code>
          domain (ETS, no database) or a pure-Elixir provider.
        </p>
      </.section>

      <div>
        <p class="mb-3 text-xs font-semibold uppercase tracking-wide text-gray-500">Capabilities</p>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.capability_card :for={{path, title, description} <- @pages} path={path} title={title} description={description} />
        </div>
      </div>
    </.page>
    """
  end
end
