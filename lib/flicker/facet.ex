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

  Type-derived defaults (deriving these fields from an Ash attribute's own
  type, per the spec's type table) are a later Spec 003 stage — this
  struct is filled in by hand for now.
  """

  @typedoc "How a facet value is cast."
  @type type :: :string | :integer | :float | :boolean | :date | :enum

  @typedoc "A comparison operator a facet value can be compared with."
  @type operator :: :eq | :neq | :gt | :gte | :lt | :lte

  @typedoc "A facet definition."
  @type t :: %__MODULE__{
          key: atom(),
          label: String.t() | nil,
          type: type(),
          operators: [operator()],
          default_op: operator(),
          values: [atom()] | nil
        }

  @enforce_keys [:key]
  defstruct key: nil, label: nil, type: :string, operators: [:eq], default_op: :eq, values: nil
end
