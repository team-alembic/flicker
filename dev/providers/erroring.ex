defmodule Dev.Providers.Erroring do
  @moduledoc """
  A `Flicker.Provider` that always fails — the dev playground's
  reproduce-on-demand fixture for the select component's themed error state
  (Spec 005).

  Dev-only — never shipped (`dev/` is excluded from `package.files`).
  """

  @behaviour Flicker.Provider

  alias Flicker.Query

  @impl true
  @doc "Always returns `{:error, :simulated_provider_failure}`, ignoring `query`/`opts`."
  @spec search(Query.t(), keyword()) :: {:error, :simulated_provider_failure}
  def search(_query, _opts), do: {:error, :simulated_provider_failure}

  @impl true
  @doc "Always returns `{:error, :simulated_provider_failure}`, ignoring `values`/`opts`."
  @spec fetch([term()], keyword()) :: {:error, :simulated_provider_failure}
  def fetch(_values, _opts), do: {:error, :simulated_provider_failure}
end
