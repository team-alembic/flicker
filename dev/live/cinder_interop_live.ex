defmodule Dev.Live.CinderInterop do
  @moduledoc """
  Playground page for [Spec 009 Level 2](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-009-cinder-interop.md)
  — `Flicker.Integrations.Cinder`, the blessed adapter, pairing
  `Flicker.search/1` with a `Cinder.collection` over the same resource with
  URL state coordinated between the two libraries.

  `Flicker.search` never lists records itself; every keystroke it emits
  `{on_change, query, filter}` to the host (Spec 003). This page composes
  that `filter` onto a base `Ash.Query` for `Dev.Music.Artist` via the
  adapter's `query/2` (no hand-rolled `Ash.Query.filter_input/2` call, the
  way [Level 1](https://github.com/team-alembic/flicker/blob/main/guides/cinder-integration.md)
  needed one) and hands the result to `Cinder.collection`'s `query` attr.
  `show_filters={false}` because Flicker owns filtering here (Spec 009's
  double-filter guidance): the two libraries never fight over the same
  field — `test/flicker/cinder_interop_test.exs` asserts
  `Flicker.Integrations.Cinder.overlapping_fields/2` over this page's
  `facet_keys/0` and `cinder_filter_fields/0` stays empty, so a Cinder
  column filter and a Flicker facet can't quietly drift onto the same
  field as either configuration changes.

  The adapter's other half is URL state: every `on_change` pushes a patch
  carrying the raw typed string under the adapter's namespaced
  `flicker_q` param (`push_patch/4`), alongside whatever Cinder's own
  `Cinder.UrlSync` is already tracking (page, sort) — reloading, sharing,
  or navigating back to a URL with `?flicker_q=...&sort=...` restores
  both libraries' state, neither clobbering the other's params.
  `handle_params/3` is where that restore happens, via the adapter's
  `restore/2`: it re-parses the raw string (never the parsed struct — the
  struct is lossy, see `Flicker.Query.t()`'s `:input` field) and feeds
  `Flicker.search/1`'s new `text` attr, adopted once on mount.

  An actor toggle proves the recipe is actor-scoped end to end: both the
  search's own suggestions and the query it composes run under
  `@actor`, and Cinder reads the resulting query under the same actor —
  so a labelled artist that actor can't see never reaches the table.
  """

  use Phoenix.LiveView
  use Cinder.UrlSync

  import Dev.UI

  alias Dev.Music.Artist
  alias Flicker.Integrations.Cinder, as: FlickerCinder

  @path "/cinder-interop"
  @facet_keys [:status, :tier, :monthly_listeners]

  # Documents (and, via the test suite, guards) Spec 009's double-filter
  # convention: Flicker owns filtering on this page (`show_filters={false}`,
  # no `<:col filter>`s), so the set of Cinder-filter-managed fields is
  # empty and `FlickerCinder.overlapping_fields/2` against `@facet_keys`
  # returns `[]` — see `Flicker.CinderInteropTest`. Sorting doesn't count:
  # `<:col sort>` on a faceted field is fine (ordering isn't filtering).
  @cinder_filter_fields []

  @actors [
    {"Public (no label)", nil},
    {"Indie label", "indie"},
    {"Major label", "major"}
  ]

  @doc "The fields this page lets Cinder's own column filters manage — exposed for the double-filter drift test."
  @spec cinder_filter_fields() :: [atom()]
  def cinder_filter_fields, do: @cinder_filter_fields

  @doc "The Flicker facet keys this page configures — exposed for the double-filter drift test."
  @spec facet_keys() :: [atom()]
  def facet_keys, do: @facet_keys

  @impl true
  @doc "Seeds `Dev.Music` and resolves this page's facet registry once."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    Dev.Music.seed!()

    socket =
      socket
      |> assign(:actors, @actors)
      |> assign(:actor_label, nil)
      |> assign(:facets, FlickerCinder.facets(%{resource: Artist, facets: @facet_keys}))

    {:ok, socket}
  end

  @impl true
  @doc """
  Restores both libraries' URL state: Cinder's own `page`/`sort` (via
  `Cinder.UrlSync.handle_params/3`) and Flicker's `flicker_q` (via
  `FlickerCinder.restore/2`, which re-parses the raw string against this
  page's own facet registry) — runs on every mount and every `push_patch`,
  so a shared link, a refresh, or the back button all reproduce the exact
  same narrowed table.
  """
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, uri, socket) do
    {text, _query, filter} = FlickerCinder.restore(params, socket.assigns.facets)

    socket =
      params
      |> Cinder.UrlSync.handle_params(uri, socket)
      |> assign(:search_text, text)
      |> assign(:filtered_query, FlickerCinder.query(base_query(), filter))

    {:noreply, socket}
  end

  # A stable sort matters beyond aesthetics: `Dev.Music`'s ETS data layer
  # returns rows in arbitrary order, so without one, which 25 rows land on
  # Cinder's first page is arbitrary too.
  defp base_query, do: Ash.Query.sort(Artist, :name)

  @impl true
  @doc "Switches the acting actor's `:label`, changing which artists Cinder can read."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("set_actor", %{"label" => label}, socket) do
    {:noreply, assign(socket, :actor_label, normalize_label(label))}
  end

  defp normalize_label(""), do: nil
  defp normalize_label(label), do: label

  @impl true
  @doc """
  Composes `Flicker.search/1`'s emitted filter onto the base query on
  every keystroke (via the adapter's `query/2`), then pushes a patch
  carrying the raw typed string under the adapter's own namespaced param
  — merged with whatever params the current URL already carries (Cinder's
  own `page`/`sort`, preserved untouched) via `push_patch/4`.
  """
  @spec handle_info({atom(), Flicker.Query.t(), map() | nil}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:artist_query_changed, query, filter}, socket) do
    socket =
      socket
      |> assign(:filtered_query, FlickerCinder.query(base_query(), filter))
      |> FlickerCinder.push_patch(@path, query, current_params(socket))

    {:noreply, socket}
  end

  # Cinder's own `<:col sort>` clicks patch their own URL directly
  # (`Cinder.Table.UrlManager`, upstream of this page); this page never
  # intercepts that, so the params it reads back here are always whatever
  # the browser's current URL — the one source of truth both libraries'
  # `push_patch` calls share — actually carries, not a stale copy from the
  defp status_badge(:active), do: "bg-green-100 text-green-800"
  defp status_badge(:on_hiatus), do: "bg-amber-100 text-amber-800"
  defp status_badge(_status), do: "bg-gray-100 text-gray-600"

  defp format_listeners(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_listeners(n) when n >= 1_000, do: "#{div(n, 1_000)}k"
  defp format_listeners(n), do: to_string(n)

  # last `handle_params/3`.
  defp current_params(socket) do
    case get_in(socket.assigns, [:url_state, :uri]) do
      nil -> %{}
      uri -> uri |> URI.parse() |> Map.get(:query) |> Kernel.||("") |> URI.decode_query()
    end
  end

  @impl true
  @doc "Renders the actor toggle, the search bar, and the Cinder collection it drives."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    assigns = assign(assigns, :actor, %{label: assigns.actor_label})

    ~H"""
    <.page title="Cinder interop (Level 2)" current_path="/cinder-interop" spec="docs/specs/spec-009-cinder-interop.md">
      <:description>
        Try <code>status:active</code>, <code>tier:legendary</code>, or free
        text — <code>Flicker.search</code> narrows the <code>Cinder.collection</code>
        below it live via <code>Flicker.Integrations.Cinder</code>. Sort a
        column, then copy the address bar: it carries both Cinder's own
        <code>sort</code> param and Flicker's namespaced <code>flicker_q</code>,
        and reloading (or pasting the URL fresh) reproduces the exact same
        narrowed, sorted table.
      </:description>

      <.actor_toggle actors={@actors} selected={@actor_label} />

      <.section label="Search + Cinder table">
        <Flicker.search
          id="artist-search"
          resource={Artist}
          actor={@actor}
          facets={@facets}
          text={@search_text}
          on_change={:artist_query_changed}
        />

        <div class="mt-4">
          <Cinder.collection
            id="artist-collection"
            query={@filtered_query}
            actor={@actor}
            show_filters={false}
            url_state={@url_state}
            theme="modern"
            page_size={10}
          >
            <:col :let={artist} field="name" sort>{artist.name}</:col>
            <:col :let={artist} field="status">
              <span class={["rounded-full px-2 py-0.5 text-xs", status_badge(artist.status)]}>
                {artist.status}
              </span>
            </:col>
            <:col :let={artist} field="tier">{artist.tier}</:col>
            <:col :let={artist} field="monthly_listeners" sort>{format_listeners(artist.monthly_listeners)}</:col>
          </Cinder.collection>
        </div>
      </.section>
    </.page>
    """
  end
end
