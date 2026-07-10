defmodule Flicker.Facet do
  @moduledoc """
  A single facet definition for faceted search.

  This is a placeholder struct: its shape exists from Spec 004 so
  `Flicker.Query.facets` and the `Flicker.Provider.facets/0` callback have a
  stable contract to compile against, but facet semantics (parsing,
  type-derived autocomplete, the cursor state machine) are
  [Spec 003](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-003-faceted-search.md)'s
  scope, not this one's.

  ## Fields

    * `:key` — the facet's identifier (e.g. `:status`).
    * `:label` — user-facing facet name.
  """

  @typedoc "A facet definition (placeholder shape; see Spec 003)."
  @type t :: %__MODULE__{
          key: atom(),
          label: String.t() | nil
        }

  @enforce_keys [:key]
  defstruct key: nil, label: nil
end
