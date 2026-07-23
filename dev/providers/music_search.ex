defmodule Dev.Providers.MusicSearch do
  @moduledoc """
  A federated `Flicker.Provider` over the whole `Dev.Music` domain —
  Artists, Albums, and Genres in one search, each tagged with a
  `Flicker.Result` `:group` and a `meta.href` — the dev playground's
  `Flicker.palette/1` demo ([Spec 008](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-005-dev-playground.md)).

  Also the playground's exercise of `facets` inside `Flicker.palette/1`
  end-to-end (Spec 008's now-closed open question): `facets/0` is Tier 2
  (`c:Flicker.Provider.facets/0`), not Tier 1 (`Flicker.Providers.AshResource.facets/1`),
  since federating three resources means there's no single resource for
  the derivation to introspect — this provider decides for itself how
  each facet key applies (`c:Flicker.Provider.search/2`'s doc): `type`
  narrows which resource *groups* are searched at all (`type:album`
  returns only albums — the natural facet for a federated search, where
  "which kind of thing" is the one dimension every group shares); `status`
  narrows `Dev.Music.Artist` results by its enum status and leaves the
  other groups untouched, since only artists carry one.

  Dev-only — never shipped (`dev/` is excluded from `package.files`).
  Group ordering here (Artists, then Albums, then Genres) is this
  provider's own choice — the palette never re-sorts by group (Spec 008).
  """

  @behaviour Flicker.Provider

  alias Dev.Music.{Album, Artist, Genre}
  alias Flicker.{Facet, Query, Result}

  @impl true
  @doc """
  Runs an `ilike`-equivalent search across `Dev.Music.Artist` (`:name`),
  `Dev.Music.Album` (`:title`), and `Dev.Music.Genre` (`:name`), returning
  every match grouped by resource, each with `meta.href` pointing at the
  dev playground's `/records/:type/:id` demo page.

  Honours `query.facets` (see the moduledoc): a `type:` facet value drops
  whichever resource groups don't match it entirely; a `status:` facet
  value narrows `Dev.Music.Artist` results to it (repeated `status:`
  tokens OR together, same as every other Flicker facet).
  """
  @spec search(Query.t(), keyword()) :: {:ok, [Result.t()]} | {:error, term()}
  def search(%Query{text: text, facets: facets}, opts) do
    actor = Keyword.get(opts, :actor)
    tenant = Keyword.get(opts, :tenant)
    limit = Keyword.get(opts, :limit, 25)
    types = facet_values(facets, :type)
    statuses = facet_values(facets, :status)

    results =
      [:artist, :album, :genre]
      |> Enum.filter(&(types == [] or &1 in types))
      |> Enum.flat_map(&group_results(&1, text, statuses, actor, tenant))
      |> Enum.take(limit)

    {:ok, results}
  rescue
    exception -> {:error, exception}
  end

  @impl true
  @doc "The facets this federated provider supports — see the moduledoc."
  @spec facets() :: [Facet.t()]
  def facets do
    [
      %Facet{
        key: :status,
        label: "Status",
        type: :enum,
        operators: [:eq],
        default_op: :eq,
        values: [:active, :inactive, :on_hiatus],
        value_labels: %{active: "Active", inactive: "Inactive", on_hiatus: "On Hiatus"}
      },
      %Facet{
        key: :type,
        label: "Type",
        type: :enum,
        operators: [:eq],
        default_op: :eq,
        values: [:artist, :album, :genre],
        value_labels: %{artist: "Artist", album: "Album", genre: "Genre"}
      }
    ]
  end

  @impl true
  @doc """
  Resolves `values` (each `"artist:<id>"`, `"album:<id>"`, or
  `"genre:<id>"`) back to `Flicker.Result` structs. Unused in the
  playground's palette (controlled mode never preselects a value), kept
  correct for completeness of the `Flicker.Provider` contract.
  """
  @spec fetch([term()], keyword()) :: {:ok, [Result.t()]} | {:error, term()}
  def fetch(values, opts) do
    actor = Keyword.get(opts, :actor)
    tenant = Keyword.get(opts, :tenant)

    results =
      values
      |> Enum.group_by(&type_of/1, &id_of/1)
      |> Enum.flat_map(&fetch_type(&1, actor, tenant))

    {:ok, results}
  end

  # One clause per federated group — the shape each needs (search fields,
  # value/label functions) lives here rather than in `search/2` itself, so
  # adding/adjusting a group's facet handling touches one clause, not the
  # fan-out.
  defp group_results(:artist, text, statuses, actor, tenant) do
    extra_filters = if statuses == [], do: [], else: [{:status, statuses}]

    resource_results(
      Artist,
      [:name],
      "artist",
      "Artists",
      & &1.name,
      & &1.status,
      text,
      actor,
      tenant,
      extra_filters
    )
  end

  defp group_results(:album, text, _statuses, actor, tenant) do
    resource_results(
      Album,
      [:title],
      "album",
      "Albums",
      & &1.title,
      & &1.track_count,
      text,
      actor,
      tenant
    )
  end

  defp group_results(:genre, text, _statuses, actor, tenant) do
    resource_results(
      Genre,
      [:name],
      "genre",
      "Genres",
      & &1.name,
      fn _ -> nil end,
      text,
      actor,
      tenant
    )
  end

  # `status:` (or any future facet another group grows) only ever narrows
  # the one group it names — a `status:` value here has no bearing on
  # Albums/Genres, since neither carries that attribute at all.
  defp facet_values(facets, key) do
    facets
    |> Enum.filter(fn {facet_key, _op, _value} -> facet_key == key end)
    |> Enum.map(fn {_facet_key, _op, value} -> value end)
  end

  defp resource_results(
         resource,
         search_fields,
         type,
         group,
         label_fun,
         sublabel_fun,
         text,
         actor,
         tenant,
         extra_filters \\ []
       ) do
    query =
      resource
      |> Ash.Query.for_read(:read, %{}, actor: actor, tenant: tenant)
      |> apply_search_filter(search_fields, text)
      |> apply_extra_filters(extra_filters)

    case Ash.read(query, actor: actor, tenant: tenant) do
      {:ok, records} -> Enum.map(records, &to_result(&1, type, group, label_fun, sublabel_fun))
      {:error, _reason} -> []
    end
  end

  defp apply_search_filter(query, _search_fields, text) when text in [nil, ""], do: query

  defp apply_search_filter(query, search_fields, text) do
    pattern = Ash.CiString.new(text)
    or_clauses = Enum.map(search_fields, &%{to_string(&1) => %{"contains" => pattern}})
    Ash.Query.filter_input(query, %{"or" => or_clauses})
  end

  defp apply_extra_filters(query, extra_filters) do
    Enum.reduce(extra_filters, query, fn {attribute, values}, query ->
      Ash.Query.filter_input(query, %{to_string(attribute) => %{"in" => values}})
    end)
  end

  defp to_result(record, type, group, label_fun, sublabel_fun) do
    %Result{
      value: "#{type}:#{record.id}",
      label: label_fun.(record),
      sublabel: sublabel_fun.(record) |> to_string_or_nil(),
      group: group,
      meta: %{href: "/records/#{type}/#{record.id}"}
    }
  end

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)

  defp type_of(value), do: value |> String.split(":", parts: 2) |> List.first()
  defp id_of(value), do: value |> String.split(":", parts: 2) |> List.last()

  defp fetch_type({"artist", ids}, actor, tenant),
    do: fetch_resource(Artist, ids, "artist", "Artists", & &1.name, actor, tenant)

  defp fetch_type({"album", ids}, actor, tenant),
    do: fetch_resource(Album, ids, "album", "Albums", & &1.title, actor, tenant)

  defp fetch_type({"genre", ids}, actor, tenant),
    do: fetch_resource(Genre, ids, "genre", "Genres", & &1.name, actor, tenant)

  defp fetch_type(_other, _actor, _tenant), do: []

  defp fetch_resource(resource, ids, type, group, label_fun, actor, tenant) do
    query =
      resource
      |> Ash.Query.for_read(:read, %{}, actor: actor, tenant: tenant)
      |> Ash.Query.filter_input(%{"id" => %{"in" => ids}})

    case Ash.read(query, actor: actor, tenant: tenant) do
      {:ok, records} -> Enum.map(records, &to_result(&1, type, group, label_fun, fn _ -> nil end))
      {:error, _reason} -> []
    end
  end
end
