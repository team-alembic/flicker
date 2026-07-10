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
    * `:target` — the Ash filter path this facet resolves to: a list of
      atoms (an attribute name, an aggregate/calculation name, or a
      relationship path ending in an attribute, e.g. `[:worker,
      :full_name]`). `nil` means `[key]`. Filled in by
      `Flicker.Providers.AshResource.facets/1` (the facet registry,
      [Spec 003](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-003-faceted-search.md));
      hand-built facets can set it directly.
    * `:related` — for a `belongs_to`/`has_*` facet, `%{resource: module}`
      describing the related resource a nested search over this facet's
      values would run against. `nil` for non-relationship facets.

  Hand-build a `Flicker.Facet` directly, or — for an Ash resource — derive
  it from `facets: [:status, :worker, ...]` via
  `Flicker.Providers.AshResource.facets/1`, which introspects the
  resource's own type system per the spec's type table and lets an
  explicit `[type:, path:, attribute:, op:]` override any derived field.
  """

  @typedoc "How a facet value is cast."
  @type type :: :string | :integer | :float | :boolean | :date | :enum

  @typedoc "A comparison operator a facet value can be compared with."
  @type operator :: :eq | :neq | :gt | :gte | :lt | :lte | :contains

  @typedoc "The related resource a `belongs_to`/`has_*` facet searches over."
  @type related :: %{resource: module()}

  @typedoc "A facet definition."
  @type t :: %__MODULE__{
          key: atom(),
          label: String.t() | nil,
          type: type(),
          operators: [operator()],
          default_op: operator(),
          values: [atom()] | nil,
          value_labels: %{atom() => String.t()} | nil,
          target: [atom()] | nil,
          related: related() | nil
        }

  @enforce_keys [:key]
  defstruct key: nil,
            label: nil,
            type: :string,
            operators: [:eq],
            default_op: :eq,
            values: nil,
            value_labels: nil,
            target: nil,
            related: nil

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
