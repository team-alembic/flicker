if Code.ensure_loaded?(Ash) do
  defmodule Flicker.Providers.AshResource do
    @moduledoc """
    The built-in `Flicker.Provider` that Tier 1 declarative component config
    compiles to (ADR-001) — searching and fetching directly off an Ash
    resource, with no provider module of your own to write.

    This module only compiles when `ash` is present (guarded by
    `Code.ensure_loaded?/1`, ADR-006): it's inert, not merely undocumented,
    in a build without `ash` in its deps.

    Every emitted `Flicker.Result` carries the underlying record as
    `meta.record` — the documented, stable way for an `:option` slot to
    render icons, badges, or anything else the two label strings can't
    express.

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
      * `:facets` — optional list of facet keys for `facets/1` to expand
        ([Spec 003](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-003-faceted-search.md)),
        and the registry `search/2` composes `Flicker.Query.to_filter/2`
        against to scope candidates by `query.facets` before the free-text
        match runs. Each entry is either a bare atom (`:status`) naming an
        attribute, relationship, aggregate, or calculation to derive a
        `Flicker.Facet.t()` from, a `{key, overrides}` pair (`status:
        [type: :enum]`) where `overrides` — any of `:type`, `:path`,
        `:attribute`, `:aggregate`, `:op`, `:label` — takes precedence over
        what introspection would derive, or an already-built `Flicker.Facet.t()`
        (passed through unchanged — how `Flicker.select/1`'s `facets:` attr
        wires this in, since it resolves to `Flicker.Facet` structs before
        reaching the provider).

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

    @default_limit 25
    @default_read_action :read

    @impl true
    @doc """
    Runs `opts[:read_action]` on `opts[:resource]`, filtering by
    `opts[:filter]` (if any), then `query.facets` (Spec 003 — distinct facet
    keys AND, repeated instances of the same key OR, composed via
    `Flicker.Query.to_filter/2` against this provider's own facet registry
    so the candidates are scoped *before* the text match runs), then
    `query.text` (case-insensitive substring match over `opts[:search]`),
    sorted by `opts[:sort]` (if any), limited to `opts[:limit]` and offset
    by `opts[:offset]` (default `0`, via `Ash.Query.offset/2` —
    [Spec 010](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-010-windowed-search.md)).
    Always actor/tenant-scoped (ADR-004).
    """
    @spec search(Query.t(), keyword()) :: {:ok, [Result.t()]} | {:error, term()}
    def search(%Query{text: text} = query, opts) do
      resource = Keyword.fetch!(opts, :resource)
      search_fields = Keyword.fetch!(opts, :search)
      actor = Keyword.get(opts, :actor)
      tenant = Keyword.get(opts, :tenant)
      limit = Keyword.get(opts, :limit, @default_limit)
      offset = Keyword.get(opts, :offset, 0)

      ash_query =
        resource
        |> Ash.Query.for_read(Keyword.get(opts, :read_action, @default_read_action), %{},
          actor: actor,
          tenant: tenant
        )
        |> apply_base_filter(Keyword.get(opts, :filter))
        |> apply_facet_filter(query, opts)
        |> apply_search_filter(search_fields, text)
        |> apply_sort(Keyword.get(opts, :sort))
        |> Ash.Query.limit(limit)
        |> Ash.Query.offset(offset)

      with {:ok, records} <- Ash.read(ash_query, actor: actor, tenant: tenant) do
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

    defp apply_facet_filter(ash_query, %Query{facets: []}, _opts), do: ash_query

    # `facets(opts)` re-derives the same `Flicker.Facet.t()` registry
    # `Flicker.Query.parse/2` was run against — `Flicker.Query.to_filter/2`
    # needs each matched key's own `:target` (a relationship path, an
    # aggregate/calc name, or a plain attribute) to build the right nested
    # filter clause, not just the bare key.
    defp apply_facet_filter(ash_query, %Query{} = query, opts) do
      Ash.Query.filter_input(ash_query, Query.to_filter(query, facets(opts)))
    end

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

    # `meta.record` is the documented public contract for this provider:
    # an `:option` slot needs the record itself for icons/badges/avatars,
    # not just the two label strings.
    defp to_result(record, opts) do
      %Result{
        value: primary_key_value(record),
        label: field_value(record, Keyword.fetch!(opts, :option_label)),
        sublabel: opts |> Keyword.get(:option_sublabel) |> optional_field_value(record),
        meta: %{record: record}
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

    # -- Facet registry ---------------------------------------------------
    #
    # The facet registry: expands `opts[:facets]` (bare keys, or `{key,
    # overrides}` pairs) into `Flicker.Facet.t()` structs by introspecting
    # `opts[:resource]`'s own type system (Spec 003's type table). This is
    # an `AshResource`-provider capability, not core (ADR-006) — a pure
    # `Flicker.Provider` supplies `facets/0` by hand instead.

    @doc """
    Expands `opts[:facets]` into `[Flicker.Facet.t()]` by introspecting
    `opts[:resource]` — the facet registry
    ([Spec 003](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-003-faceted-search.md)).

    Each entry in `opts[:facets]` is a bare atom (`:status`) naming an
    attribute, relationship, aggregate, or calculation on the resource, or
    a `{key, overrides}` pair layering `:type`, `:path`, `:attribute`,
    `:aggregate`, `:op`, or `:label` on top of what introspection would
    derive. Per the spec's type table:

      * an `Ash.Type.Enum` (or a plain attribute with a `one_of`
        constraint) derives `type: :enum`, `:eq`-only, `:values`, and
        `:value_labels` (the enum's own labels, or a humanised fallback);
        a value outside `:values` is rejected by the parser (degrades to
        free text) rather than reaching a filter.
      * `:boolean` derives `type: :boolean`, `:eq`-only.
      * a date/datetime attribute derives `type: :date`, operators `:eq`
        `:gte` `:lt` (relative values like `7d` are the parser's concern —
        see `Flicker.Query`).
      * `:integer`/`:decimal`/`:float` derive numeric `type`, the full
        comparison operator set.
      * a `belongs_to`/`has_*` relationship derives a `:string`-typed
        facet (the related record's id) with `:related` set to
        `%{resource: destination}` — the nested-search descriptor a
        recursive Flicker search would run over — and `:target` resolved
        to the relationship's own filter path (the source attribute for
        `belongs_to`, `[name, primary_key]` for `has_*`).
      * an aggregate or calculation derives from its own resolved Ash type
        the same way an attribute would (numeric, boolean, ...).
      * anything else (plain `:string`, or a field introspection can't
        find) derives `type: :string`, `:contains`-only — free `ilike`,
        no picklist.

    `overrides[:path]` (a relationship path ending in an attribute, e.g.
    `[:worker, :full_name]`) and `overrides[:attribute]` /
    `overrides[:aggregate]` (an explicit field name, when it differs from
    the facet `key`) redirect which field is introspected;
    `overrides[:type]` and `overrides[:op]` replace the derived `:type` /
    `:default_op` outright.
    """
    @spec facets(keyword()) :: [Flicker.Facet.t()]
    def facets(opts) do
      resource = Keyword.fetch!(opts, :resource)

      opts
      |> Keyword.get(:facets, [])
      |> Enum.map(&derive_facet(resource, &1))
    end

    # An already-built `%Flicker.Facet{}` entry (e.g. `facets:` mixing
    # `resource:` Tier 1 derivation with a hand-built facet, see
    # `Flicker.FacetSuggest.resolve_facets/1`) passes through unchanged —
    # it's already what this function would otherwise produce, and feeding
    # a struct through `derive_facet/2`'s atom/tuple clauses would raise.
    defp derive_facet(_resource, %Flicker.Facet{} = facet), do: facet

    defp derive_facet(resource, key) when is_atom(key), do: derive_facet(resource, {key, []})

    defp derive_facet(resource, {key, overrides}) when is_atom(key) and is_list(overrides) do
      resource
      |> base_facet(key, overrides)
      |> apply_overrides(overrides)
    end

    defp base_facet(resource, key, overrides) do
      cond do
        Keyword.has_key?(overrides, :path) ->
          facet_from_path(resource, key, Keyword.fetch!(overrides, :path))

        Keyword.has_key?(overrides, :aggregate) ->
          facet_from_field(resource, key, Keyword.fetch!(overrides, :aggregate))

        Keyword.has_key?(overrides, :attribute) ->
          facet_from_field(resource, key, Keyword.fetch!(overrides, :attribute))

        true ->
          facet_from_field(resource, key, key)
      end
    end

    defp facet_from_field(resource, key, field_name) do
      cond do
        attribute = Ash.Resource.Info.attribute(resource, field_name) ->
          field_facet(key, [field_name], attribute.type, attribute.constraints)

        relationship = Ash.Resource.Info.relationship(resource, field_name) ->
          relationship_facet(key, relationship)

        aggregate = Ash.Resource.Info.aggregate(resource, field_name) ->
          {:ok, type} = Ash.Resource.Info.aggregate_type(resource, aggregate)
          field_facet(key, [field_name], type, [])

        calculation = Ash.Resource.Info.calculation(resource, field_name) ->
          field_facet(key, [field_name], calculation.type, calculation.constraints || [])

        true ->
          field_facet(key, [field_name], nil, [])
      end
    end

    # A relationship path (`overrides[:path]`) ending in an attribute on
    # the resource it walks to — e.g. `[:worker, :full_name]` walks the
    # `:worker` relationship, then reads `:full_name` off its destination.
    defp facet_from_path(resource, key, path) do
      {relationship_names, [attribute_name]} = Enum.split(path, -1)
      destination = Enum.reduce(relationship_names, resource, &relationship_destination(&2, &1))
      attribute = Ash.Resource.Info.attribute(destination, attribute_name)

      case attribute do
        nil -> field_facet(key, path, nil, [])
        attribute -> field_facet(key, path, attribute.type, attribute.constraints)
      end
    end

    defp relationship_destination(resource, name) do
      %{destination: destination} = Ash.Resource.Info.relationship(resource, name)
      destination
    end

    defp relationship_facet(key, relationship) do
      destination = relationship.destination

      %Flicker.Facet{
        key: key,
        type: :string,
        operators: [:eq],
        default_op: :eq,
        target: relationship_target(relationship),
        related: %{
          resource: destination,
          search: related_search_fields(destination),
          option_label: related_option_label(destination)
        }
      }
    end

    # Picks a default search/label field for the related resource's nested
    # search (Spec 003): `:name`, then `:title`, then the first public
    # string attribute, then the primary key itself — always something,
    # never an empty list, so the nested search never has nothing to match
    # or display against.
    defp related_search_fields(resource) do
      cond do
        Ash.Resource.Info.attribute(resource, :name) -> [:name]
        Ash.Resource.Info.attribute(resource, :title) -> [:title]
        field = first_public_string_attribute(resource) -> [field]
        true -> Ash.Resource.Info.primary_key(resource)
      end
    end

    defp related_option_label(resource) do
      case related_search_fields(resource) do
        [field | _] -> field
      end
    end

    defp first_public_string_attribute(resource) do
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.find(&(&1.type == Ash.Type.String))
      |> case do
        nil -> nil
        attribute -> attribute.name
      end
    end

    defp relationship_target(%Ash.Resource.Relationships.BelongsTo{source_attribute: source_attribute}),
      do: [source_attribute]

    defp relationship_target(relationship) do
      [primary_key] = Ash.Resource.Info.primary_key(relationship.destination)
      [relationship.name, primary_key]
    end

    defp field_facet(key, target, type, constraints) do
      struct!(
        Flicker.Facet,
        [key: key, target: target] ++ Map.to_list(type_fields(type, constraints))
      )
    end

    defp type_fields(type, constraints) do
      cond do
        enum_type?(type) ->
          values = type.values()

          %{
            type: :enum,
            operators: [:eq],
            default_op: :eq,
            values: values,
            value_labels: enum_labels(type, values)
          }

        one_of = Keyword.get(constraints, :one_of) ->
          %{
            type: :enum,
            operators: [:eq],
            default_op: :eq,
            values: one_of,
            value_labels: humanized_labels(one_of)
          }

        type == Ash.Type.Boolean ->
          %{type: :boolean, operators: [:eq], default_op: :eq}

        type in [
          Ash.Type.Date,
          Ash.Type.UtcDatetime,
          Ash.Type.UtcDatetimeUsec,
          Ash.Type.NaiveDatetime
        ] ->
          %{type: :date, operators: [:eq, :gte, :lt], default_op: :eq}

        type == Ash.Type.Integer ->
          %{type: :integer, operators: [:eq, :neq, :gt, :gte, :lt, :lte], default_op: :eq}

        type in [Ash.Type.Decimal, Ash.Type.Float] ->
          %{type: :float, operators: [:eq, :neq, :gt, :gte, :lt, :lte], default_op: :eq}

        true ->
          %{type: :string, operators: [:contains], default_op: :contains}
      end
    end

    defp enum_type?(type) do
      is_atom(type) and type not in [nil] and Code.ensure_loaded?(type) and
        function_exported?(type, :values, 0) and function_exported?(type, :label, 1)
    end

    defp enum_labels(type, values), do: Map.new(values, &{&1, type.label(&1)})

    defp humanized_labels(values), do: Map.new(values, &{&1, humanize(&1)})

    defp humanize(value) do
      value
      |> to_string()
      |> String.split("_")
      |> Enum.map_join(" ", &String.capitalize/1)
    end

    defp apply_overrides(facet, overrides) do
      facet
      |> apply_label_override(Keyword.get(overrides, :label))
      |> apply_type_override(Keyword.get(overrides, :type))
      |> apply_op_override(Keyword.get(overrides, :op))
      |> apply_value_colors_override(Keyword.get(overrides, :value_colors))
    end

    defp apply_label_override(facet, nil), do: facet
    defp apply_label_override(facet, label), do: %{facet | label: label}

    defp apply_value_colors_override(facet, nil), do: facet

    defp apply_value_colors_override(facet, colors) when is_map(colors), do: %{facet | value_colors: colors}

    defp apply_type_override(facet, nil), do: facet

    defp apply_type_override(facet, type) do
      {operators, default_op} = type_default_ops(type)
      %{facet | type: type, operators: operators, default_op: default_op}
    end

    defp type_default_ops(:enum), do: {[:eq], :eq}
    defp type_default_ops(:boolean), do: {[:eq], :eq}
    defp type_default_ops(:date), do: {[:eq, :gte, :lt], :eq}

    defp type_default_ops(type) when type in [:integer, :float], do: {[:eq, :neq, :gt, :gte, :lt, :lte], :eq}

    defp type_default_ops(:string), do: {[:contains], :contains}

    defp apply_op_override(facet, nil), do: facet

    defp apply_op_override(facet, op) do
      op = normalize_op(op)
      %{facet | default_op: op, operators: Enum.uniq([op | facet.operators])}
    end

    # `overrides[:op]` accepts the operator's canonical name (`:gte`) or the
    # symbol form the spec's registry example writes (`:>=`) — either
    # reads naturally in config.
    defp normalize_op(:>=), do: :gte
    defp normalize_op(:<=), do: :lte
    defp normalize_op(:!=), do: :neq
    defp normalize_op(:>), do: :gt
    defp normalize_op(:<), do: :lt
    defp normalize_op(:==), do: :eq
    defp normalize_op(op), do: op
  end
end
