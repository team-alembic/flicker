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

  `opts` (a keyword list) carries `:actor`, `:tenant`, `:limit`, and any
  provider-specific configuration. Reads are always actor/tenant-scoped
  (ADR-004) — providers that wrap an authorisation-aware source must honour
  `:actor`/`:tenant` themselves; `Flicker.Providers.AshResource` does this
  by passing them straight through to Ash.

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

  @optional_callbacks facets: 0, render_option: 2

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
