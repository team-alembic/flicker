defmodule Flicker.ProviderTest do
  use ExUnit.Case, async: true

  alias Flicker.{Provider, Query, Result}
  alias Flicker.Providers.Static

  defmodule BareModule do
    @moduledoc false
    @behaviour Flicker.Provider

    @impl true
    def search(_query, _opts), do: {:ok, []}

    @impl true
    def fetch(_values, _opts), do: {:ok, []}
  end

  defmodule LimitEcho do
    @moduledoc false
    @behaviour Flicker.Provider

    @impl true
    def search(_query, opts), do: {:ok, [%Result{value: opts[:limit], label: "limit"}]}

    @impl true
    def fetch(_values, _opts), do: {:ok, []}
  end

  defmodule Failing do
    @moduledoc false
    @behaviour Flicker.Provider

    @impl true
    def search(_query, _opts), do: {:error, :boom}

    @impl true
    def fetch(_values, _opts), do: {:error, :boom}
  end

  defmodule Raising do
    @moduledoc false
    @behaviour Flicker.Provider

    @impl true
    def search(_query, _opts), do: raise("kaboom")

    @impl true
    def fetch(_values, _opts), do: raise("kaboom")
  end

  defmodule Malformed do
    @moduledoc false
    @behaviour Flicker.Provider

    @impl true
    def search(_query, _opts), do: :not_a_valid_shape

    @impl true
    def fetch(_values, _opts), do: :not_a_valid_shape
  end

  @results [
    %Result{value: 1, label: "Casey Cassidy", sublabel: "Rock"},
    %Result{value: 2, label: "Alex Rivers", sublabel: "Jazz"}
  ]

  describe "run_search/3" do
    test "invokes the provider's search/2 and returns its results" do
      assert {:ok, [%Result{label: "Casey Cassidy"}]} =
               Provider.run_search({Static, results: @results}, %Query{text: "cas"})
    end

    test "accepts a bare module (no static opts)" do
      assert {:ok, []} = Provider.run_search(BareModule, %Query{text: ""})
    end

    test "merges per-call opts over the provider's static opts" do
      assert {:ok, [%Result{value: 5}]} =
               Provider.run_search({LimitEcho, limit: 1}, %Query{text: ""}, limit: 5)
    end

    test "normalises a provider's {:error, term} return" do
      assert {:error, :boom} = Provider.run_search(Failing, %Query{text: ""})
    end

    test "normalises an exception raised by the provider" do
      assert {:error, {:provider_raised, %RuntimeError{}}} =
               Provider.run_search(Raising, %Query{text: ""})
    end

    test "normalises a malformed provider return" do
      assert {:error, {:invalid_provider_result, :not_a_valid_shape}} =
               Provider.run_search(Malformed, %Query{text: ""})
    end
  end

  describe "run_fetch/3" do
    test "invokes the provider's fetch/2 and returns its results" do
      assert {:ok, [%Result{value: 2, label: "Alex Rivers"}]} =
               Provider.run_fetch({Static, results: @results}, [2])
    end

    test "resolves multiple values in one call, omitting unresolvable ones" do
      assert {:ok, results} = Provider.run_fetch({Static, results: @results}, [1, 2, 999])
      assert length(results) == 2
    end
  end
end
