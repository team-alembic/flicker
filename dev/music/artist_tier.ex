defmodule Dev.Music.ArtistTier do
  @moduledoc """
  A career-tier `Ash.Type.Enum` for `Dev.Music.Artist` — used alongside
  `:status` (a plain `:atom` with a `one_of` constraint) so Spec 003's
  facet registry test suite covers both enum shapes the type table
  describes: a true `Ash.Type.Enum` module (this one, with its own
  `label/1`) and a bare constrained attribute (`:status`).
  """

  use Ash.Type.Enum,
    values: [emerging: "Emerging", established: "Established", legendary: "Legendary"]
end
