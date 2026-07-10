defmodule Dev.Providers.Slow do
  @moduledoc """
  A `Flicker.Provider` wrapping `Flicker.Providers.Static` with a
  configurable artificial delay — the dev playground's reproduce-on-demand
  fixture for loading, debounce, and stale-result-cancellation behaviour
  (Spec 005).

  Configure it with `{Dev.Providers.Slow, results: [...], latency_ms: 1_000}`
  (`:latency_ms` defaults to 1000). Dev-only — never shipped (`dev/` is
  excluded from `package.files`).
  """

  @behaviour Flicker.Provider

  alias Flicker.{Providers.Static, Query, Result}

  @default_latency_ms 1_000

  @impl true
  @doc "Sleeps `opts[:latency_ms]` (default #{@default_latency_ms}ms), then delegates to `Flicker.Providers.Static.search/2`."
  @spec search(Query.t(), keyword()) :: {:ok, [Result.t()]} | {:error, term()}
  def search(query, opts) do
    Process.sleep(Keyword.get(opts, :latency_ms, @default_latency_ms))
    Static.search(query, opts)
  end

  @impl true
  @doc "Sleeps `opts[:latency_ms]` (default #{@default_latency_ms}ms), then delegates to `Flicker.Providers.Static.fetch/2`."
  @spec fetch([term()], keyword()) :: {:ok, [Result.t()]} | {:error, term()}
  def fetch(values, opts) do
    Process.sleep(Keyword.get(opts, :latency_ms, @default_latency_ms))
    Static.fetch(values, opts)
  end
end
