defmodule Flicker.Providers.StaticTest do
  use ExUnit.Case, async: true

  alias Flicker.Providers.Static
  alias Flicker.{Query, Result}

  @results [
    %Result{value: 1, label: "Casey Cassidy", sublabel: "Rock"},
    %Result{value: 2, label: "Alex Rivers", sublabel: "Jazz"},
    %Result{value: 3, label: "Jordan Blake", sublabel: nil}
  ]

  describe "search/2" do
    test "blank query returns the full listing" do
      assert {:ok, results} = Static.search(%Query{text: ""}, results: @results)
      assert length(results) == 3
    end

    test "matches label case-insensitively" do
      assert {:ok, [%Result{label: "Casey Cassidy"}]} =
               Static.search(%Query{text: "cas"}, results: @results)
    end

    test "matches sublabel" do
      assert {:ok, [%Result{label: "Alex Rivers"}]} =
               Static.search(%Query{text: "jazz"}, results: @results)
    end

    test "a nil sublabel doesn't blow up matching" do
      assert {:ok, [%Result{label: "Jordan Blake"}]} =
               Static.search(%Query{text: "jordan"}, results: @results)
    end

    test "respects limit" do
      assert {:ok, results} = Static.search(%Query{text: ""}, results: @results, limit: 1)
      assert length(results) == 1
    end

    test "no match returns an empty list" do
      assert {:ok, []} = Static.search(%Query{text: "nonexistent"}, results: @results)
    end
  end

  describe "fetch/2" do
    test "resolves multiple values in one call" do
      assert {:ok, results} = Static.fetch([1, 3], results: @results)
      assert Enum.map(results, & &1.value) |> Enum.sort() == [1, 3]
    end

    test "silently omits unresolvable values" do
      assert {:ok, results} = Static.fetch([1, 999], results: @results)
      assert [%Result{value: 1}] = results
    end
  end
end
