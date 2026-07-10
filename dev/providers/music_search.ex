defmodule Dev.Providers.MusicSearch do
  @moduledoc """
  A federated `Flicker.Provider` over the whole `Dev.Music` domain —
  Artists, Albums, and Genres in one search, each tagged with a
  `Flicker.Result` `:group` and a `meta.href` — the dev playground's
  `Flicker.palette/1` demo ([Spec 008](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-005-dev-playground.md)).

  Dev-only — never shipped (`dev/` is excluded from `package.files`).
  Group ordering here (Artists, then Albums, then Genres) is this
  provider's own choice — the palette never re-sorts by group (Spec 008).
  """

  @behaviour Flicker.Provider

  alias Dev.Music.{Album, Artist, Genre}
  alias Flicker.{Query, Result}

  require Ash.Query

  @impl true
  @doc """
  Runs an `ilike`-equivalent search across `Dev.Music.Artist` (`:name`),
  `Dev.Music.Album` (`:title`), and `Dev.Music.Genre` (`:name`), returning
  every match grouped by resource, each with `meta.href` pointing at the
  dev playground's `/records/:type/:id` demo page.
  """
  @spec search(Query.t(), keyword()) :: {:ok, [Result.t()]} | {:error, term()}
  def search(%Query{text: text}, opts) do
    actor = Keyword.get(opts, :actor)
    tenant = Keyword.get(opts, :tenant)
    limit = Keyword.get(opts, :limit, 25)

    results =
      [
        resource_results(
          Artist,
          [:name],
          "artist",
          "Artists",
          & &1.name,
          & &1.status,
          text,
          actor,
          tenant
        ),
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
        ),
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
      ]
      |> List.flatten()
      |> Enum.take(limit)

    {:ok, results}
  rescue
    exception -> {:error, exception}
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

  defp resource_results(resource, search_fields, type, group, label_fun, sublabel_fun, text, actor, tenant) do
    query =
      resource
      |> Ash.Query.for_read(:read, %{}, actor: actor, tenant: tenant)
      |> apply_search_filter(search_fields, text)

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
