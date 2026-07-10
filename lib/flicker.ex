defmodule Flicker do
  @moduledoc """
  Flicker is an Ash-native searchable select / combobox / faceted-search
  library for Phoenix LiveView.

  It reads directly off Ash resources — no options plumbing — authorises via
  `actor:` and Ash policies, and derives facet behaviour from the Ash type
  system. Where Cinder is for tables, Flicker is for searching, filtering,
  and selecting records.

  This module is the library's namespace root; it holds no runtime API of
  its own. The building blocks:

    * `Flicker.Provider` — the behaviour every data source implements
      (`search/2`, `fetch/2`), and the internal invocation boundary
      (`run_search/3`, `run_fetch/3`) core code calls through.
    * `Flicker.Result` — the display struct providers return.
    * `Flicker.Query` — the search request struct passed to `search/2`.
    * `Flicker.Facet` — the (currently placeholder) faceted-search struct.
    * `Flicker.Providers.Static` — an in-memory reference provider, useful
      as a test double or for small fixed option lists.
    * `Flicker.Providers.AshResource` — the built-in provider Tier 1
      declarative component config compiles to.

  See the guides for how the component layer (built on top of this
  contract) is configured.
  """
end
