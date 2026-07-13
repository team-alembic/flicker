if Code.ensure_loaded?(Ash) and Code.ensure_loaded?(Cinder) do
  defmodule Flicker.Integrations.Cinder do
    @moduledoc """
    The optional Level 2 adapter from [Spec 009](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-009-cinder-interop.md):
    removes the `Flicker.search/1` + `Cinder.collection/1` boilerplate
    [Level 1](https://github.com/team-alembic/flicker/blob/main/guides/cinder-integration.md)
    leaves to the host, and coordinates URL state between the two
    libraries.

    This module only compiles when both `ash` and `cinder` are present
    (`Code.ensure_loaded?/1`, the same [ADR-006](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-006-core-depends-only-on-provider.md)
    pattern `Flicker.Providers.AshResource` and `Flicker.AshPhoenixForm`
    use): it's inert, not merely undocumented, in a build without `cinder`
    in its deps — the core suite passes with no changes required.

    ## Query composition

    `query/2` is Level 1's `base_query/1` recipe, generalised: given a base
    `Ash.Resource.t()` or `Ash.Query.t()` and the `filter` half of
    `Flicker.search/1`'s `on_change` payload, it returns the composed
    `Ash.Query.t()` for `Cinder.collection`'s `query` attr.

        alias Flicker.Integrations.Cinder, as: FlickerCinder

        def handle_info({:artist_query_changed, query, filter}, socket) do
          socket =
            socket
            |> assign(:filtered_query, FlickerCinder.query(Artist, filter))
            |> FlickerCinder.push_patch("/artists", query)

          {:noreply, socket}
        end

    ## URL state

    Both libraries want query params: Cinder's own `Cinder.UrlSync` owns
    `page`, `sort`, `page_size`, `search`, `after`, `before`, plus one
    param per filterable column field name (verified against `cinder`
    `~> 0.15`'s `Cinder.UrlSync.build_url/3` — see that module's
    `known_collection_keys` and its `_filter_fields` metadata key). A bare
    `?q=` risks colliding with a column literally named `q`; this adapter
    reserves `"flicker_q"` (`url_param/0`) — prefixed distinctly enough
    that no realistic column name collides with it, and disjoint from
    Cinder's own reserved names — as the one param it ever reads or
    writes. This resolves Spec 009's open question on namespacing
    convention; see that spec's Open Questions section for the decision
    record.

    Serialisation round-trips `Flicker.Query.t()`'s `:input` field — the
    verbatim string the user typed — never `:text` or a reconstruction of
    `:facets` (both are lossy: facet tokens are stripped from `:text`,
    and `:facets`' cast values can't reproduce the original literal, e.g.
    `TRUE` vs. `true`, or `7d` vs. the date it resolved to). Restoring a
    shared URL re-`Flicker.Query.parse/2`s that exact string, the same way
    the host's own `Flicker.search/1` instance would have.

        alias Flicker.Integrations.Cinder, as: FlickerCinder

        def handle_params(params, uri, socket) do
          facets = FlickerCinder.facets(%{resource: Artist, facets: [:status, :tier]})
          {text, _query, filter} = FlickerCinder.restore(params, facets)

          socket =
            params
            |> Cinder.UrlSync.handle_params(uri, socket)
            |> assign(:search_text, text)
            |> assign(:filtered_query, FlickerCinder.query(Artist, filter))

          {:noreply, socket}
        end

        # render/1
        # <Flicker.search id="artist-search" text={@search_text} resource={Artist} ... />

    `text` (a new optional attr on `Flicker.search/1`) is adopted once, on
    the component's first mount only — it pre-populates the input from the
    restored string without fighting the component's own ownership of
    what the user types next.

    ## Double-filter UX

    Flicker's facets and Cinder's own column filters (`filter`/`filter_fn`
    on a `<:col>`, or `show_filters`) can both narrow the same collection.
    The convention: **a field is filtered in one place, not both** — pick
    whichever owns it. When Flicker owns filtering for the whole
    collection (the common case: one search bar above the table), pass
    `show_filters={false}` to `Cinder.collection` so its own filter UI
    doesn't render at all (see the playground page and guide). When a
    column needs filtering that no Flicker facet covers, let Cinder's own
    column filter own that one field instead — never configure a Flicker
    facet and a Cinder column filter over the same field at once, since
    the two would apply independently (an unsatisfiable AND, not visible
    to either component) and confuse users who cleared one filter and
    still see narrowed results.

    `overlapping_fields/2` is a drift guard for that convention: given the
    facet keys configured on a `Flicker.search/1` and the field names a
    `Cinder.collection`'s columns declare `filter` on, it returns the
    fields governed by both — empty when the convention holds. A test
    asserting this list stays empty catches a column filter and a facet
    quietly drifting onto the same field as either configuration changes.
    """

    alias Flicker.{FacetSuggest, Query}

    @url_param "flicker_q"

    @typedoc "An Ash resource module, or an already-built `Ash.Query.t()`."
    @type queryable :: Ash.Resource.t() | Ash.Query.t()

    @doc """
    The URL param name this adapter reserves for Flicker's own query
    state (`"flicker_q"`) — namespaced against `cinder`'s own `UrlSync`-managed
    params (see the moduledoc for how this was chosen).
    """
    @spec url_param() :: String.t()
    def url_param, do: @url_param

    @doc """
    Composes `filter` (the third element of `Flicker.search/1`'s
    `on_change` payload) onto `base` — an `Ash.Resource.t()` or an
    already-built `Ash.Query.t()` — via `Ash.Query.filter_input/2`. A
    `nil` filter (the search box cleared) is treated as `%{}`, Ash's own
    "no filter" shape, so `base` comes back unfiltered rather than
    raising. This is the whole of Level 1's `base_query/1` recipe, so a
    host can drop that private function entirely and call this instead.
    """
    @spec query(queryable(), map() | nil) :: Ash.Query.t()
    def query(base, filter \\ nil)
    def query(base, nil), do: query(base, %{})
    def query(base, filter), do: Ash.Query.filter_input(base, filter)

    @doc """
    Resolves the facet registry for `assigns` (e.g. `%{resource: Artist,
    facets: [:status, :tier]}`) the same way `Flicker.search/1` does
    internally — so `restore/2` (and any other Ash-aware `Flicker.Query`
    function keyed off the facet registry) sees the identical
    `Flicker.Facet.t()` list the live component parses against, without
    the host re-implementing Tier 1 introspection by hand.
    """
    @spec facets(map()) :: [Flicker.Facet.t()]
    def facets(assigns), do: FacetSuggest.resolve_facets(assigns)

    @doc """
    Reads the raw Flicker input string back out of `params` (as produced
    by `encode_params/1` / `put_params/2`), defaulting to `""` when the
    param is absent — a fresh visit with no shared search.
    """
    @spec decode_input(map()) :: String.t()
    def decode_input(params), do: Map.get(params, @url_param, "")

    @doc """
    The full URL-restore step for `handle_params/3`: reads the raw input
    string out of `params`, re-`Flicker.Query.parse/2`s it against
    `facet_defs`, and returns `{input, query, filter}` — `input` to seed
    `Flicker.search/1`'s new `text` attr, `query`/`filter` to seed the
    same composed query `query/2` would build from a live `on_change`.

    Given `Flicker.Query.parse/2`'s own guarantees (pure, never raises),
    this never raises either — an absent or malformed param degrades to
    an empty query exactly the way an empty search box does.
    """
    @spec restore(map(), [Flicker.Facet.t()]) :: {String.t(), Query.t(), map()}
    def restore(params, facet_defs \\ []) do
      input = decode_input(params)
      parsed = Query.parse(input, facet_defs)
      filter = Query.to_filter(parsed, facet_defs)
      {input, parsed, filter}
    end

    @doc """
    Encodes `query.input` (the verbatim typed string — the round-trip
    source of truth, never `:text` or a reconstruction of `:facets`) as
    the URL param map this adapter owns. A cleared/empty query encodes as
    `%{}` so the param disappears from the URL entirely rather than
    persisting an empty `flicker_q=`.
    """
    @spec encode_params(Query.t()) :: %{optional(String.t()) => String.t()}
    def encode_params(%Query{input: input}) when input in [nil, ""], do: %{}
    def encode_params(%Query{input: input}), do: %{@url_param => input}

    @doc """
    Merges `query`'s encoded param into `existing_params` (e.g. the
    current URL's own query params, or Cinder's own encoded collection
    state), replacing any prior `#{@url_param}` value — the rest of
    `existing_params` (Cinder's own managed keys, or any other custom
    param a host tracks) passes through untouched, so neither library's
    state clobbers the other's.
    """
    @spec put_params(map(), Query.t()) :: map()
    def put_params(existing_params, query) do
      existing_params
      |> Map.delete(@url_param)
      |> Map.merge(encode_params(query))
    end

    @doc """
    Pushes a `push_patch/2` to `path` with `existing_params` merged with
    `query`'s encoded param (via `put_params/2`) — the one-call
    `handle_info`-side counterpart to `restore/2`'s `handle_params/3`
    side. Drop the query string entirely (navigate to bare `path`) when
    the merged params end up empty, rather than a trailing `?`.
    """
    @spec push_patch(Phoenix.LiveView.Socket.t(), String.t(), Query.t(), map()) ::
            Phoenix.LiveView.Socket.t()
    def push_patch(socket, path, query, existing_params \\ %{}) do
      params = put_params(existing_params, query)

      to =
        case URI.encode_query(params) do
          "" -> path
          query_string -> path <> "?" <> query_string
        end

      Phoenix.LiveView.push_patch(socket, to: to)
    end

    @doc """
    Returns the fields present in both `facet_keys` (a `Flicker.search/1`'s
    configured facet keys, e.g. `[:status, :tier]`) and `cinder_fields`
    (the field names a `Cinder.collection`'s `<:col filter>`s declare) —
    a violation of the double-filter convention (see the moduledoc).
    Compares by string, so atoms and strings on either side both work;
    returns `[]` when the convention holds.
    """
    @spec overlapping_fields([atom() | String.t()], [atom() | String.t()]) :: [String.t()]
    def overlapping_fields(facet_keys, cinder_fields) do
      cinder_set = MapSet.new(cinder_fields, &to_string/1)

      facet_keys
      |> Enum.map(&to_string/1)
      |> Enum.filter(&MapSet.member?(cinder_set, &1))
    end
  end
end
