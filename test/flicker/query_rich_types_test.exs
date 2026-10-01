defmodule Flicker.QueryRichTypesTest do
  @moduledoc """
  The rich facet grammar reaching `Flicker.Query.parse/2` end to end (Spec
  018): range and list literals, presets, the new operators, and how each
  shapes an Ash filter through `to_filter/2`.

  `Flicker.FacetCastTest` covers casting in isolation; this covers the
  integration — that a typed token becomes the right `{key, operator, value}`
  and then the right filter map.
  """

  use ExUnit.Case, async: true

  alias Flicker.Facet
  alias Flicker.Facet.Range
  alias Flicker.Query

  @today ~D[2026-07-29]
  @opts [today: @today]

  @created Facet.new(key: :created, type: :date_range)
  @price Facet.new(key: :price, type: :number_range, bounds: %{min: 0, max: 500})
  @status Facet.new(key: :status, type: :enum, values: [:active, :inactive, :archived], multiple?: true)
  @length Facet.new(key: :length, type: :duration)
  @facets [@created, @price, @status, @length]

  defp parse(input), do: Query.parse(input, @facets, @opts)

  describe "range literals through the parser" do
    test "a closed range becomes a single :between match" do
      assert parse("created:2026-06-01..2026-06-30").facets == [
               {:created, :between, %Range{from: ~D[2026-06-01], to: ~D[2026-06-30]}}
             ]
    end

    test "half-open ranges keep the endpoint they have" do
      assert parse("created:..2026-06-30").facets == [
               {:created, :between, %Range{from: nil, to: ~D[2026-06-30]}}
             ]

      assert parse("created:2026-06-01..").facets == [
               {:created, :between, %Range{from: ~D[2026-06-01], to: nil}}
             ]
    end

    test "the bare `:` form resolves to :between via the facet's default_op" do
      assert [{:created, :between, _}] = parse("created:2026-07-01").facets
    end

    test "a range token coexists with free text and other facets" do
      query = parse("created:2026-06-01..2026-06-30 price:10..50 some words")

      assert [{:created, :between, _}, {:price, :between, _}] = query.facets
      assert query.text == "some words"
    end

    test "a reversed range is reported, not filtered" do
      query = parse("created:2026-07-30..2026-07-01")

      assert query.facets == []
      assert [%Query.Invalid{key: :created, reason: :reversed_range}] = query.invalid
    end

    test "input round-trips: re-parsing :input reproduces the query" do
      for input <- [
            "created:2026-06-01..2026-06-30",
            "created:last-30-days",
            "created:..2026-06-30",
            "price:10..50",
            "status:active,archived",
            "length:2h30m"
          ] do
        query = parse(input)

        assert Query.parse(query.input, @facets, @opts) == query, "#{input} did not round-trip"
      end
    end
  end

  describe "presets through the parser" do
    test "a preset token resolves and stays tagged" do
      assert parse("created:last-30-days").facets == [
               {:created, :between, %Range{from: ~D[2026-06-30], to: @today, preset: :last_30_days}}
             ]
    end

    test "all-time parses to an unbounded range" do
      assert [{:created, :between, %Range{from: nil, to: nil, preset: :all_time}}] =
               parse("created:all-time").facets
    end

    test "an unknown preset-looking word is reported as a bad date" do
      assert [%Query.Invalid{reason: :bad_date}] = parse("created:last-3000-days").invalid
    end
  end

  describe "list literals through the parser" do
    test "a comma list becomes one :in match" do
      assert parse("status:active,archived").facets == [{:status, :in, [:active, :archived]}]
    end

    test "!= becomes :not_in" do
      assert parse("status!=active,archived").facets == [{:status, :not_in, [:active, :archived]}]
    end

    test "a single value keeps :eq, so pre-018 parses are unchanged" do
      assert parse("status:active").facets == [{:status, :eq, :active}]
    end

    test "a quoted value keeps its commas" do
      facet = Facet.new(key: :name, type: :string)

      assert Query.parse(~s(name:"Nguyen, Casey"), [facet]).facets == [{:name, :eq, "Nguyen, Casey"}]
    end

    test "a trailing comma is reported — the mid-typing state" do
      assert [%Query.Invalid{reason: :incomplete_list}] = parse("status:active,").invalid
    end
  end

  describe "durations through the parser" do
    test "compound durations cast to seconds" do
      assert parse("length:2h30m").facets == [{:length, :eq, 9_000}]
    end

    test "comparison operators work on durations" do
      assert parse("length>=15m").facets == [{:length, :gte, 900}]
    end
  end

  describe "to_filter/2 with the new operators" do
    @describetag :ash

    test "a closed range becomes a bounded and-pair" do
      assert "created:2026-06-01..2026-06-30" |> parse() |> Query.to_filter(@facets) ==
               %{"created" => %{"and" => [%{"gte" => ~D[2026-06-01]}, %{"lte" => ~D[2026-06-30]}]}}
    end

    test "a half-open range contributes only the bound it has" do
      assert "price:10.." |> parse() |> Query.to_filter(@facets) == %{"price" => %{"gte" => 10}}
      assert "price:..50" |> parse() |> Query.to_filter(@facets) == %{"price" => %{"lte" => 50}}
    end

    test "an unbounded range contributes no clause at all" do
      # `all-time` means "don't filter by date", not "match nothing".
      assert "created:all-time" |> parse() |> Query.to_filter(@facets) == %{}
    end

    test "an unbounded range alongside a real facet leaves the other one intact" do
      assert "created:all-time price:10..50" |> parse() |> Query.to_filter(@facets) ==
               %{"price" => %{"and" => [%{"gte" => 10}, %{"lte" => 50}]}}
    end

    test ":in and :not_in map onto Ash's own forms" do
      assert "status:active,archived" |> parse() |> Query.to_filter(@facets) ==
               %{"status" => %{"in" => [:active, :archived]}}

      assert "status!=active,archived" |> parse() |> Query.to_filter(@facets) ==
               %{"status" => %{"not" => %{"in" => [:active, :archived]}}}
    end

    test "distinct facets AND together" do
      filter = "created:2026-06-01..2026-06-30 status:active" |> parse() |> Query.to_filter(@facets)

      assert %{"and" => clauses} = filter
      assert length(clauses) == 2
    end

    test "repeated range facets OR together, per Spec 003" do
      filter = "created:2026-06-01..2026-06-02 created:2026-07-01..2026-07-02" |> parse() |> Query.to_filter(@facets)

      # `or` wraps outside with the key repeated inside, matching the shape
      # Spec 003 already established for repeated scalar facets.
      assert %{"or" => [%{"created" => _}, %{"created" => _}]} = filter
    end

    test "an invalid token contributes nothing to the filter" do
      assert "price:900" |> parse() |> Query.to_filter(@facets) == %{}
    end

    test "a range resolves through a relationship path like any other facet" do
      facet = Facet.new(key: :signed, type: :date_range, target: [:contract, :signed_on])

      assert "signed:2026-06-01..2026-06-30" |> Query.parse([facet], @opts) |> Query.to_filter([facet]) ==
               %{"contract" => %{"signed_on" => %{"and" => [%{"gte" => ~D[2026-06-01]}, %{"lte" => ~D[2026-06-30]}]}}}
    end
  end

  describe "parse/3 stays total" do
    test "no input raises, for any facet type" do
      facets = [
        @created,
        @price,
        @status,
        @length,
        Facet.new(key: :at, type: :datetime_range),
        Facet.new(key: :name, type: :string)
      ]

      inputs = [
        "",
        "..",
        "created:..",
        "created:...",
        "price:,,",
        "status:,",
        "created:2026-06-01..2026-06-02..2026-06-03",
        ~s(name:"unterminated),
        "created:😀",
        "price:" <> String.duplicate("9", 400),
        "length:99999999999999999999d",
        "status:" <> String.duplicate("active,", 200)
      ]

      for input <- inputs do
        assert %Query{} = Query.parse(input, facets, @opts)
      end
    end
  end
end
