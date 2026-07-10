if Code.ensure_loaded?(Ash) do
  defmodule Flicker.Providers.AshResource do
    @moduledoc """
    The built-in `Flicker.Provider` that Tier 1 declarative component config
    compiles to (ADR-001) — searching and fetching directly off an Ash
    resource, with no provider module of your own to write.

    This module only compiles when `ash` is present (guarded by
    `Code.ensure_loaded?/1`, ADR-006): it's inert, not merely undocumented,
    in a build without `ash` in its deps.

    Configure it with `{Flicker.Providers.AshResource, opts}`:

      * `:resource` — required. The Ash resource module to read.
      * `:search` — required list of attribute names `search/2`'s `ilike`-style
        (case-insensitive substring) match runs over.
      * `:option_label` — required. An attribute name, or a
        `fun(record) :: String.t()`, producing each result's `:label`.
      * `:option_sublabel` — optional. An attribute name, or a
        `fun(record) :: String.t() | nil`, producing each result's
        `:sublabel`.
      * `:read_action` — the read action to run. Defaults to `:read`.
      * `:limit` — max results for `search/2`. Defaults to `25`.
      * `:sort` — sort applied to `search/2`'s query (any `Ash.Query.sort/2`
        input). Optional.
      * `:filter` — a base filter (any `Ash.Query.filter_input/2` input)
        applied before the search-text match. Optional.

    `:actor`, `:tenant`, and `:limit` also arrive per-call, merged in by
    `Flicker.Provider.run_search/3` / `run_fetch/3` — reads are always
    actor/tenant-scoped (ADR-004): this provider passes them straight
    through to `Ash.Query.for_read/4` and `Ash.read/2`, and never bypasses
    policies.

    `fetch/2` resolves all of `values` in a single `primary_key in ^values`
    read (ADR-003) — one query, not one per value — and silently omits
    values that don't resolve (deleted records, or records a policy now
    hides): this is a normal partial result, not an error.

    Composite primary keys aren't supported yet — `fetch/2` assumes a
    single-attribute primary key.
    """

    @behaviour Flicker.Provider

    alias Flicker.{Query, Result}

    require Ash.Query

    @default_limit 25
    @default_read_action :read

    @impl true
    @doc """
    Runs `opts[:read_action]` on `opts[:resource]`, filtering by
    `opts[:filter]` (if any) and then `query.text` (case-insensitive
    substring match over `opts[:search]`), sorted by `opts[:sort]` (if any),
    limited to `opts[:limit]`. Always actor/tenant-scoped (ADR-004).
    """
    @spec search(Query.t(), keyword()) :: {:ok, [Result.t()]} | {:error, term()}
    def search(%Query{text: text}, opts) do
      resource = Keyword.fetch!(opts, :resource)
      search_fields = Keyword.fetch!(opts, :search)
      actor = Keyword.get(opts, :actor)
      tenant = Keyword.get(opts, :tenant)
      limit = Keyword.get(opts, :limit, @default_limit)

      query =
        resource
        |> Ash.Query.for_read(Keyword.get(opts, :read_action, @default_read_action), %{},
          actor: actor,
          tenant: tenant
        )
        |> apply_base_filter(Keyword.get(opts, :filter))
        |> apply_search_filter(search_fields, text)
        |> apply_sort(Keyword.get(opts, :sort))
        |> Ash.Query.limit(limit)

      with {:ok, records} <- Ash.read(query, actor: actor, tenant: tenant) do
        {:ok, Enum.map(records, &to_result(&1, opts))}
      end
    end

    @impl true
    @doc """
    Resolves `values` against `opts[:resource]`'s primary key in a single
    `primary_key in ^values` read (ADR-003). Values that don't resolve are
    simply absent from the result — not an error.
    """
    @spec fetch([term()], keyword()) :: {:ok, [Result.t()]} | {:error, term()}
    def fetch([], _opts), do: {:ok, []}

    def fetch(values, opts) do
      resource = Keyword.fetch!(opts, :resource)
      actor = Keyword.get(opts, :actor)
      tenant = Keyword.get(opts, :tenant)
      [primary_key] = Ash.Resource.Info.primary_key(resource)

      query =
        resource
        |> Ash.Query.for_read(Keyword.get(opts, :read_action, @default_read_action), %{},
          actor: actor,
          tenant: tenant
        )
        |> Ash.Query.filter_input(%{to_string(primary_key) => %{"in" => values}})

      with {:ok, records} <- Ash.read(query, actor: actor, tenant: tenant) do
        {:ok, Enum.map(records, &to_result(&1, opts))}
      end
    end

    defp apply_base_filter(query, nil), do: query
    defp apply_base_filter(query, filter), do: Ash.Query.filter_input(query, filter)

    defp apply_search_filter(query, _search_fields, text) when text in [nil, ""], do: query

    defp apply_search_filter(query, search_fields, text) do
      # `Ash.CiString` on the right-hand side forces `contains/2`'s
      # case-insensitive overload regardless of the field's own type — the
      # `ilike`-equivalent this provider promises, portable across data
      # layers (works on `Ash.DataLayer.Ets`, not just Postgres `ILIKE`).
      pattern = Ash.CiString.new(text)

      or_clauses =
        Enum.map(search_fields, fn field ->
          %{to_string(field) => %{"contains" => pattern}}
        end)

      Ash.Query.filter_input(query, %{"or" => or_clauses})
    end

    defp apply_sort(query, nil), do: query
    defp apply_sort(query, sort), do: Ash.Query.sort(query, sort)

    defp to_result(record, opts) do
      %Result{
        value: primary_key_value(record),
        label: field_value(record, Keyword.fetch!(opts, :option_label)),
        sublabel: opts |> Keyword.get(:option_sublabel) |> optional_field_value(record),
        meta: %{}
      }
    end

    defp primary_key_value(record) do
      [primary_key] = Ash.Resource.Info.primary_key(record.__struct__)
      Map.fetch!(record, primary_key)
    end

    defp field_value(record, fun) when is_function(fun, 1), do: fun.(record)
    defp field_value(record, field) when is_atom(field), do: Map.fetch!(record, field)

    defp optional_field_value(nil, _record), do: nil
    defp optional_field_value(field_or_fun, record), do: field_value(record, field_or_fun)
  end
end
