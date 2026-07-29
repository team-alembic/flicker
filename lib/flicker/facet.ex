defmodule Flicker.Facet do
  @moduledoc """
  A facet definition for faceted search ([Spec 003](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-003-faceted-search.md)).

  A facet definition tells `Flicker.Query.parse/2` how to recognise a
  `key:value` token in typed input: which key it answers to, what shape a
  value must have to count as a match rather than degrading to free text,
  and which comparison operators (`>=`, `<`, `!=`, ...) are legal for it.

  ## Fields

    * `:key` — the facet's identifier, matched against the token's key
      (e.g. `:status` matches `status:active`).
    * `:label` — user-facing facet name (used by later Spec 003 stages —
      autocomplete, the cursor state machine — not by the parser itself).
    * `:type` — how a raw value string is cast. One of `:string`
      (default, no casting), `:integer`, `:float`, `:boolean`, `:date`
      (ISO 8601, or a relative offset like `7d` / `2w` / `1m` / `1y`), or
      `:enum` (the raw value must match one of `:values`).
    * `:operators` — comparison operators this facet accepts when the user
      types them explicitly (`after>=7d`). Defaults to `[:eq]`. A value not
      built from this list degrades the whole token to free text.
    * `:default_op` — the operator used for the bare `:` form
      (`after:7d`). Defaults to `:eq`; a date facet meaning "after" would
      set this to `:gte`. Should be a member of `:operators`.
    * `:values` — for `:type: :enum`, the closed list of atoms a value may
      cast to. A value not in this list degrades to free text. Ignored for
      other types.
    * `:value_labels` — for `:type: :enum`, a map of value atom to its
      user-facing label (an `Ash.Type.Enum`'s own `label/1`, or a humanised
      fallback for a plain `one_of`-constrained attribute). `nil` for other
      types.
    * `:value_colors` — optional map of value atom to a host-supplied colour
      string (any CSS colour), shown as a dot on that value's facet pill
      (Spec 017). `nil` for no colours; unlisted values render uncoloured.
    * `:target` — the Ash filter path this facet resolves to: a list of
      atoms (an attribute name, an aggregate/calculation name, or a
      relationship path ending in an attribute, e.g. `[:worker,
      :full_name]`). `nil` means `[key]`. Filled in by
      `Flicker.Providers.AshResource.facets/1` (the facet registry,
      [Spec 003](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-003-faceted-search.md));
      hand-built facets can set it directly.
    * `:related` — for a `belongs_to`/`has_*` facet, `%{resource: module,
      search: [atom()], option_label: atom() | (struct() -> String.t())}`
      describing the related resource a nested search over this facet's
      values would run against (the same `Flicker.Providers.AshResource`
      `:search`/`:option_label` shape, so the nested search is a plain
      inner `Flicker.select`-style provider call) — `nil` for
      non-relationship facets.

  Hand-build a `Flicker.Facet` directly, or — for an Ash resource — derive
  it from `facets: [:status, :worker, ...]` via
  `Flicker.Providers.AshResource.facets/1`, which introspects the
  resource's own type system per the spec's type table and lets an
  explicit `[type:, path:, attribute:, op:]` override any derived field.
  """

  alias Flicker.Facet.{Cast, Preset}

  @typedoc "How a facet value is cast."
  @type type ::
          :string
          | :integer
          | :float
          | :boolean
          | :date
          | :datetime
          | :enum
          | :date_range
          | :datetime_range
          | :number_range
          | :duration

  @typedoc "A comparison operator a facet value can be compared with."
  @type operator :: :eq | :neq | :gt | :gte | :lt | :lte | :contains | :between | :in | :not_in

  @typedoc "Advisory numeric bounds for an editor, and a validation floor/ceiling."
  @type bounds :: %{
          optional(:min) => number(),
          optional(:max) => number(),
          optional(:step) => number()
        }

  @typedoc "Whether to request a match count per value for this facet."
  @type counted :: boolean()

  @typedoc "An extra validator run after a successful cast, on the cast value."
  @type validator :: (term() -> :ok | {:error, {atom(), map()}} | {:error, String.t()})

  @typedoc "The related resource a `belongs_to`/`has_*` facet searches over."
  @type related :: %{
          resource: module(),
          search: [atom()],
          option_label: atom() | (struct() -> String.t())
        }

  @typedoc "A facet definition."
  @type t :: %__MODULE__{
          key: atom(),
          label: String.t() | nil,
          type: type(),
          operators: [operator()],
          default_op: operator(),
          values: [atom()] | nil,
          value_labels: %{atom() => String.t()} | nil,
          value_colors: %{atom() => String.t()} | nil,
          target: [atom()] | nil,
          related: related() | nil,
          scalar: type() | nil,
          bounds: bounds() | nil,
          presets: [Flicker.Facet.Preset.t()] | nil,
          suggested: [atom()] | nil,
          multiple?: boolean(),
          editor: module() | nil,
          validate: validator() | nil,
          count: counted()
        }

  @enforce_keys [:key]
  defstruct key: nil,
            label: nil,
            type: :string,
            operators: [:eq],
            default_op: :eq,
            values: nil,
            value_labels: nil,
            value_colors: nil,
            target: nil,
            related: nil,
            scalar: nil,
            bounds: nil,
            presets: nil,
            suggested: nil,
            multiple?: false,
            editor: nil,
            validate: nil,
            count: false

  @doc """
  Builds a facet, filling in the defaults implied by its `:type` for any
  field the caller didn't set.

  Prefer this to a bare struct literal for the range types: a
  `%Flicker.Facet{type: :date_range}` literal keeps the struct's own
  `operators: [:eq]` default, which no range value can satisfy, so
  `created:2026-06-01..2026-06-30` would degrade to free text. `new/1` gives
  it `[:between]` instead.

  Only *absent* keys are defaulted — an explicit `operators:` always wins,
  including an explicit `[:eq]`.

  ## Examples

      iex> Flicker.Facet.new(key: :created, type: :date_range).operators
      [:between]

      iex> Flicker.Facet.new(key: :created, type: :date_range).scalar
      :date

      iex> Flicker.Facet.new(key: :price, type: :number_range).scalar
      :integer

      iex> Flicker.Facet.new(key: :status, type: :enum, operators: [:eq]).operators
      [:eq]

      iex> Flicker.Facet.new(key: :name).type
      :string
  """
  @spec new(keyword() | map()) :: t()
  def new(fields) do
    fields = Map.new(fields)
    type = Map.get(fields, :type, :string)

    struct!(__MODULE__, Map.merge(type_defaults(type), fields))
  end

  defp type_defaults(:date_range),
    do: %{type: :date_range, operators: [:between], default_op: :between, scalar: :date, presets: Preset.builtin()}

  defp type_defaults(:datetime_range),
    do: %{
      type: :datetime_range,
      operators: [:between],
      default_op: :between,
      scalar: :datetime,
      presets: Preset.builtin()
    }

  defp type_defaults(:number_range),
    do: %{type: :number_range, operators: [:between], default_op: :between, scalar: :integer}

  defp type_defaults(type) when type in [:integer, :float, :date, :datetime, :duration],
    do: %{type: type, operators: [:eq, :neq, :gt, :gte, :lt, :lte], default_op: :eq}

  defp type_defaults(type) when type in [:boolean, :enum], do: %{type: type, operators: [:eq, :neq], default_op: :eq}

  defp type_defaults(:string), do: %{type: :string, operators: [:eq, :neq, :contains], default_op: :eq}

  @doc """
  The type each endpoint of a range facet casts as — `:scalar` when set,
  otherwise the one implied by the range type. For a non-range facet this is
  just its own type, so callers can use it unconditionally.

  ## Examples

      iex> Flicker.Facet.scalar(%Flicker.Facet{key: :created, type: :date_range})
      :date

      iex> Flicker.Facet.scalar(%Flicker.Facet{key: :price, type: :number_range, scalar: :float})
      :float

      iex> Flicker.Facet.scalar(%Flicker.Facet{key: :name, type: :string})
      :string
  """
  @spec scalar(t()) :: type() | nil
  def scalar(%__MODULE__{scalar: nil, type: type}), do: default_scalar(type)
  def scalar(%__MODULE__{scalar: scalar}), do: scalar

  defp default_scalar(:date_range), do: :date
  defp default_scalar(:datetime_range), do: :datetime
  defp default_scalar(:number_range), do: :integer
  defp default_scalar(type), do: type

  @doc """
  Whether this facet's cast value is a `Flicker.Facet.Range`.

  ## Examples

      iex> Flicker.Facet.range?(%Flicker.Facet{key: :created, type: :date_range})
      true

      iex> Flicker.Facet.range?(%Flicker.Facet{key: :created, type: :date})
      false
  """
  @spec range?(t()) :: boolean()
  def range?(%__MODULE__{type: type}), do: type in Cast.range_types()

  @doc """
  Casts `raw` for this facet — delegates to `Flicker.Facet.Cast.cast/4`.

  Returns `{:ok, operator, value}` with the operator *resolved*: casting can
  refine it, so `:` on a range facet comes back as `:between` and a
  comma-separated list on a `multiple?: true` facet as `:in`.

  ## Examples

      iex> facet = Flicker.Facet.new(key: :created, type: :date_range)
      ...> Flicker.Facet.cast_value(facet, "2026-06-01..2026-06-30", :between)
      {:ok, :between, %Flicker.Facet.Range{from: ~D[2026-06-01], to: ~D[2026-06-30]}}
  """
  @spec cast_value(t(), String.t(), operator(), keyword()) ::
          {:ok, operator(), term()} | {:error, {atom(), map()}}
  def cast_value(facet, raw, operator, opts \\ []), do: Cast.cast(facet, raw, operator, opts)

  @doc """
  Validates `raw` for this facet without keeping the value — `:ok`, or
  `{:error, {reason, params}}` naming what was wrong
  ([ADR-012](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-012-parse-reports-invalid-facet-tokens.md)).

  ## Examples

      iex> facet = Flicker.Facet.new(key: :status, type: :enum, values: [:active, :inactive])
      ...> Flicker.Facet.validate_value(facet, "activ", :eq)
      {:error, {:not_in_values, %{value: "activ", values: [:active, :inactive]}}}

      iex> facet = Flicker.Facet.new(key: :status, type: :enum, values: [:active])
      ...> Flicker.Facet.validate_value(facet, "active", :eq)
      :ok
  """
  @spec validate_value(t(), String.t(), operator(), keyword()) :: :ok | {:error, {atom(), map()}}
  def validate_value(facet, raw, operator, opts \\ []), do: Cast.validate(facet, raw, operator, opts)

  @doc """
  This facet's value candidates, as a `Flicker.Provider` source — or `nil` for
  a facet whose values aren't drawn from a set.

  Per [ADR-011](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-011-facet-editors-are-modal-subcontexts.md),
  a set-valued facet is edited by a nested `Flicker.select`, and the only thing
  that differs between an enum facet and a relationship facet is the provider
  behind it. This is the accessor that erases that difference: one editor
  module, one counting path, one suggestion path.

  `:enum` and `:boolean` resolve to a `Flicker.Providers.Static` over their own
  closed set, with display labels from `:value_labels`, so an enum editor shows
  `Established` rather than `established` and Spec 017's `:value_colors` key
  off the same value atoms. A relationship facet resolves to the same
  `Flicker.Providers.AshResource` source `Flicker.FacetSuggest.related_search/3`
  already builds — that clause only exists when `ash` is present (ADR-006), so
  an enum facet's `Static` source keeps working without it.

  **This is about candidate values, not about controls.** Which editor opens
  for a type is a separate mapping (Spec 019): `:boolean` appears here because
  its `true`/`false` pair is genuinely a closed set worth suggesting, but it is
  edited by a switch and never opens a select.

  ## Examples

      iex> facet =
      ...>   Flicker.Facet.new(
      ...>     key: :status,
      ...>     type: :enum,
      ...>     values: [:active],
      ...>     value_labels: %{active: "Active"}
      ...>   )
      ...>
      ...> {Flicker.Providers.Static, results: [result]} = Flicker.Facet.value_source(facet)
      ...> {result.value, result.label}
      {:active, "Active"}

      iex> facet = Flicker.Facet.new(key: :verified?, type: :boolean)
      ...> {Flicker.Providers.Static, results: results} = Flicker.Facet.value_source(facet)
      ...> Enum.map(results, & &1.value)
      [true, false]

      iex> Flicker.Facet.value_source(Flicker.Facet.new(key: :created, type: :date_range))
      nil
  """
  @spec value_source(t()) :: {module(), keyword()} | nil
  def value_source(%__MODULE__{type: :enum, values: values} = facet) when is_list(values) do
    {Flicker.Providers.Static, results: Enum.map(values, &value_result(facet, &1))}
  end

  def value_source(%__MODULE__{type: :boolean}) do
    {Flicker.Providers.Static,
     results: [
       %Flicker.Result{value: true, label: "true"},
       %Flicker.Result{value: false, label: "false"}
     ]}
  end

  if Code.ensure_loaded?(Ash) do
    def value_source(%__MODULE__{related: %{resource: resource} = related}) do
      {Flicker.Providers.AshResource, resource: resource, search: related.search, option_label: related.option_label}
    end
  end

  def value_source(%__MODULE__{}), do: nil

  defp value_result(facet, value) do
    %Flicker.Result{value: value, label: value_label(facet, value)}
  end

  @doc """
  A single value's display label — `:value_labels` when it has an entry,
  otherwise the value as a string.

  ## Examples

      iex> facet = %Flicker.Facet{key: :status, value_labels: %{active: "Currently active"}}
      ...> Flicker.Facet.value_label(facet, :active)
      "Currently active"

      iex> Flicker.Facet.value_label(%Flicker.Facet{key: :status}, :active)
      "active"
  """
  @spec value_label(t(), term()) :: String.t()
  def value_label(%__MODULE__{value_labels: labels}, value) do
    case labels do
      %{^value => label} -> label
      _ -> to_string(value)
    end
  end

  @doc """
  The Ash filter path this facet resolves to: `facet.target`, or `[facet.key]`
  when `:target` is `nil`.

  ## Examples

      iex> Flicker.Facet.target(%Flicker.Facet{key: :status})
      [:status]

      iex> Flicker.Facet.target(%Flicker.Facet{key: :worker, target: [:worker, :full_name]})
      [:worker, :full_name]
  """
  @spec target(t()) :: [atom()]
  def target(%__MODULE__{target: nil, key: key}), do: [key]
  def target(%__MODULE__{target: target}), do: target
end
