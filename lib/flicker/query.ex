defmodule Flicker.Query do
  @moduledoc """
  A search request passed to `c:Flicker.Provider.search/2`.

  ## Fields

    * `:text` — the raw search text, as typed. Providers decide how to
      match it (the built-in `Flicker.Providers.AshResource` runs `ilike`
      over its configured search fields); an empty string is a valid query
      (the picker's open-with-no-input state — providers typically return a
      default listing rather than an empty result set).
    * `:facets` — active facet filters. Defaults to `[]` and stays empty
      until [Spec 003](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-003-faceted-search.md);
      the field exists now so the contract doesn't churn later.
  """

  @typedoc "A search request."
  @type t :: %__MODULE__{
          text: String.t(),
          facets: [Flicker.Facet.t()]
        }

  @enforce_keys [:text]
  defstruct text: nil, facets: []
end
