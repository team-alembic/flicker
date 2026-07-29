defmodule Flicker.Provider do
  @moduledoc """
  The behaviour every Flicker data source implements.

  `Flicker.Provider` is the escape hatch of the two-tier architecture (see
  ADR-001): the common case is Tier 1 declarative resource config, which
  compiles down to `{Flicker.Providers.AshResource, opts}` at mount, but
  anything needing federated search, a non-Ash source, or custom shaping
  implements this behaviour directly.

  A provider is identified by a module, or a `{module, opts}` tuple carrying
  static configuration for that provider (e.g. the Ash resource, its search
  fields, its read action). Core code never calls a provider's callbacks
  directly — it always goes through `run_search/3` or `run_fetch/3`, the
  single internal invocation boundary, so error normalisation and other
  cross-cutting behaviour live in one place.

  ## Callbacks

    * `search/2` — required. Returns results matching a `Flicker.Query`.
    * `fetch/2` — required. Resolves a list of previously-selected values
      back to `Flicker.Result` structs in one call (ADR-003) — not one call
      per value. Values that no longer resolve (deleted records, or records
      a policy now hides) are simply absent from the result list; this is
      normal, not an error.
    * `facets/0` — optional. Returns the facets this provider supports
      ([Spec 003](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-003-faceted-search.md)).
    * `render_option/2` — optional. Custom option rendering, given a
      `Flicker.Result` and the component's assigns.

  `opts` (a keyword list) carries `:actor`, `:tenant`, `:limit`, `:offset`,
  and any provider-specific configuration. Reads are always actor/tenant-scoped
  (ADR-004) — providers that wrap an authorisation-aware source must honour
  `:actor`/`:tenant` themselves; `Flicker.Providers.AshResource` does this
  by passing them straight through to Ash.

  ## Windowed search (`:offset`, [Spec 010](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-010-windowed-search.md))

  `:offset` (a non-negative integer, default `0`) is an additive, optional
  `search/2` opt: `Flicker.select/1`'s `paginate` attr passes an increasing
  `:offset` (`window * limit`) to fetch the next window of results, which
  get appended to what's already loaded rather than replacing it.
  `Flicker.Providers.AshResource` honours it via `Ash.Query.offset/2`;
  `Flicker.Providers.Static` honours it via `Enum.slice/3`.

  A provider that doesn't implement `:offset` simply ignores the opt and
  keeps returning its first window every time — this is safe, never an
  error, and never causes an infinite request loop: core detects the
  no-progress (a window's first result identical to the previous window's)
  and marks the list complete after at most one extra probe request.
  Omitting `:offset` entirely (the default, non-paginated path) behaves
  exactly as it always has.

  ## Error philosophy

  A provider returns `{:error, term}` on failure; it never needs to raise
  for an expected failure mode. Core rendering code renders a themed error
  state and never crashes on a provider error — `run_search/3` and
  `run_fetch/3` additionally catch unexpected exceptions and normalise them
  into `{:error, term}` so a misbehaving provider can't crash the caller.

  ## Writing your own provider

  The full contract is two callbacks:

      defmodule MyApp.Providers.Http do
        @behaviour Flicker.Provider

        @impl true
        def search(%Flicker.Query{text: text}, _opts) do
          # ... call an external API, map results to `Flicker.Result` ...
          {:ok, [%Flicker.Result{value: "42", label: "Example"}]}
        end

        @impl true
        def fetch(values, _opts) do
          # ... resolve `values` in one call; omit ones that don't resolve ...
          {:ok, []}
        end
      end

  `Flicker.Providers.Static` is a small worked example — an in-memory list
  provider used as the reference implementation and as a test double.
  """

  alias Flicker.{Query, Result}

  @typedoc "A provider module, or a `{module, opts}` tuple carrying static config."
  @type t :: module() | {module(), keyword()}

  @doc """
  Returns results matching `query`.

  `opts` carries `:actor`, `:tenant`, `:limit`, and provider-specific
  configuration.

  A provider decides for itself how to honour `query.facets` (Spec 003):
  `Flicker.Providers.AshResource` composes `Flicker.Query.to_filter/2` into
  its Ash query, scoping the candidates before `query.text`'s match runs;
  `Flicker.Providers.Static` matches `query.text` only and ignores
  `query.facets` entirely (see its moduledoc). A hand-written provider that
  doesn't support facets is free to do the same — `query.facets` being
  non-empty is never an error.
  """
  @callback search(query :: Query.t(), opts :: keyword()) ::
              {:ok, [Result.t()]} | {:error, term()}

  @doc """
  Resolves `values` — a list, not a single value (ADR-003) — to
  `Flicker.Result` structs in one call.

  Values that don't resolve (deleted records, or records a policy now
  hides) are simply absent from the returned list; this is a normal,
  partial result, not an error.
  """
  @callback fetch(values :: [term()], opts :: keyword()) ::
              {:ok, [Result.t()]} | {:error, term()}

  @doc "Returns the facets this provider supports. Optional."
  @callback facets() :: [Flicker.Facet.t()]

  @doc "Renders a custom option. Optional."
  @callback render_option(result :: Result.t(), assigns :: map()) :: term()

  @doc """
  Counts how many records each of `facets`' values would match
  ([Spec 021](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-021-facet-value-counts.md)).
  Optional.

  Returns counts keyed by facet key, then by value — the same cast values
  `Flicker.Query.parse/2` produces, so a caller needs no normalisation to look
  one up. A value absent from the map means "not counted", which is distinct
  from a value present with `0`.

  Three requirements a correct implementation has to meet
  ([ADR-014](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-014-facet-counts-are-provider-computed-and-actor-scoped.md)):

    * **Actor-scoped.** `opts` carries `:actor` and `:tenant` exactly as
      `search/2` receives them, and the count must run through the same
      authorised read. A count over records the actor can't see discloses
      cardinality — and for a small set, existence. If counting under
      authorisation isn't possible, return no count rather than an unscoped
      one.
    * **Drill-down-correct.** For each facet, apply every *other* active facet
      and the free text, but **not** that facet's own clause. Counting against
      the full query instead makes every sibling value read `0` the moment
      anything is selected, which destroys the information the user wanted.
    * **Batched.** All requested facets arrive in one call so an
      implementation can issue one query rather than N.
  """
  @callback facet_counts(query :: Query.t(), facets :: [Flicker.Facet.t()], opts :: keyword()) ::
              {:ok, %{atom() => %{term() => non_neg_integer()}}} | {:error, term()}

  @optional_callbacks facets: 0, render_option: 2, facet_counts: 3

  @doc """
  Runs `search/2` on `provider`, normalising the result.

  This is the single internal invocation boundary for search — core code
  never calls a provider's `search/2` directly. `provider` is a module or a
  `{module, provider_opts}` tuple; `provider_opts` (the provider's static
  config) is merged with `opts` (the per-call options), with `opts` taking
  precedence on key collisions.

  Always returns `{:ok, [Flicker.Result.t()]}` or `{:error, term()}` — a
  provider that raises, or returns a malformed shape, is normalised into
  `{:error, term()}` rather than propagating.
  """
  @spec run_search(t(), Query.t(), keyword()) :: {:ok, [Result.t()]} | {:error, term()}
  def run_search(provider, %Query{} = query, opts \\ []) do
    invoke(provider, :search, [query], opts)
  end

  @doc """
  Runs `fetch/2` on `provider`, normalising the result.

  This is the single internal invocation boundary for fetch — core code
  never calls a provider's `fetch/2` directly. See `run_search/3` for the
  `provider`/`opts` merging rule and the error-normalisation guarantee.
  """
  @spec run_fetch(t(), [term()], keyword()) :: {:ok, [Result.t()]} | {:error, term()}
  def run_fetch(provider, values, opts \\ []) when is_list(values) do
    invoke(provider, :fetch, [values], opts)
  end

  @doc """
  Runs `facet_counts/3` on `provider`, or returns `{:ok, %{}}` when the
  provider doesn't implement it.

  The empty-map fallback is deliberate: callers render counts by lookup with a
  `nil` default, so "this provider can't count" and "this value wasn't counted"
  collapse to the same rendering path and no call site needs a
  `function_exported?/3` branch.

  ## Examples

      iex> Flicker.Provider.run_facet_counts(Flicker.Providers.Static, %Flicker.Query{text: ""}, [])
      {:ok, %{}}
  """
  @spec run_facet_counts(term(), Query.t(), [Flicker.Facet.t()], keyword()) ::
          {:ok, %{atom() => %{term() => non_neg_integer()}}} | {:error, term()}
  def run_facet_counts(provider, query, facets, opts \\ [])

  def run_facet_counts(_provider, _query, [], _opts), do: {:ok, %{}}

  def run_facet_counts(provider, %Query{} = query, facets, opts) do
    {module, _provider_opts} = normalise(provider)

    if function_exported?(module, :facet_counts, 3) do
      invoke_counts(provider, query, facets, opts)
    else
      {:ok, %{}}
    end
  end

  defp invoke_counts(provider, query, facets, opts) do
    {module, provider_opts} = normalise(provider)
    merged_opts = Keyword.merge(provider_opts, opts)

    case apply(module, :facet_counts, [query, facets, merged_opts]) do
      {:ok, counts} when is_map(counts) -> {:ok, counts}
      {:error, _reason} = error -> error
      other -> {:error, {:invalid_provider_result, other}}
    end
  rescue
    exception -> {:error, {:provider_raised, exception}}
  catch
    kind, reason -> {:error, {:provider_raised, {kind, reason}}}
  end

  defp invoke(provider, callback, args, opts) do
    {module, provider_opts} = normalise(provider)
    merged_opts = Keyword.merge(provider_opts, opts)

    module
    |> apply(callback, args ++ [merged_opts])
    |> normalise_result()
  rescue
    exception -> {:error, {:provider_raised, exception}}
  catch
    kind, reason -> {:error, {:provider_raised, {kind, reason}}}
  end

  defp normalise({module, provider_opts}) when is_atom(module) and is_list(provider_opts), do: {module, provider_opts}

  defp normalise(module) when is_atom(module), do: {module, []}

  defp normalise_result({:ok, results}) when is_list(results) do
    if Enum.all?(results, &match?(%Result{}, &1)) do
      {:ok, results}
    else
      {:error, {:invalid_provider_result, results}}
    end
  end

  defp normalise_result({:error, _reason} = error), do: error
  defp normalise_result(other), do: {:error, {:invalid_provider_result, other}}
end
