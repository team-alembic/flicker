defmodule Flicker.QueryPropertyTest do
  @moduledoc """
  Property-tests `Flicker.Query.parse/2` against arbitrary input — quotes,
  escapes, adjacent tokens, unicode, malformed operators — per Spec 003's
  "arbitrary typing must never error" acceptance criterion.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Flicker.Facet
  alias Flicker.Query

  @facets [
    %Facet{key: :status, type: :enum, values: [:active, :inactive]},
    %Facet{key: :worker},
    %Facet{key: :after, type: :date, default_op: :gte, operators: [:gte, :lt]},
    %Facet{key: :session_count, type: :integer, operators: [:eq, :neq, :gt, :gte, :lt, :lte]}
  ]

  defp any_char do
    one_of([
      string(:alphanumeric, length: 1),
      member_of(~w[: > < ! = " \\ \s \t \n a b 7 é 😀 " _ ? -])
    ])
  end

  defp adversarial_input do
    map(list_of(any_char(), max_length: 60), &Enum.join/1)
  end

  property "never raises, for arbitrary strings built from grammar-relevant characters" do
    check all(input <- adversarial_input()) do
      assert %Query{} = Query.parse(input, @facets)
    end
  end

  property "never raises for fully arbitrary Unicode binaries" do
    check all(input <- string(:utf8, max_length: 200)) do
      assert %Query{} = Query.parse(input, @facets)
    end
  end

  property "a quoted value round-trips through a known string facet" do
    check all(value <- string(:printable, min_length: 0, max_length: 30) |> filter(&(&1 not in ["", "\n"]))) do
      facets = [%Facet{key: :worker}]
      escaped = value |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")
      input = ~s(worker:"#{escaped}")

      assert %Query{text: "", facets: [{:worker, :eq, ^value}]} = Query.parse(input, facets)
    end
  end

  property "an unknown key never produces a facet match" do
    check all(
            key <- string(:alphanumeric, min_length: 1, max_length: 10),
            value <- string(:alphanumeric, min_length: 1, max_length: 10)
          ) do
      # `key` is drawn independently of `@facets`' keys, so as long as it
      # doesn't collide, this must degrade to free text.
      if key not in ~w(status worker after session_count) do
        input = "#{key}:#{value}"
        assert %Query{facets: []} = Query.parse(input, @facets)
      end
    end
  end

  property "adjacent facet and free-text tokens never bleed into each other" do
    check all(
            op <- member_of([:eq, :neq, :gt, :gte, :lt, :lte]),
            amount <- integer(0..1000),
            free1 <- string(:alphanumeric, min_length: 1, max_length: 8),
            free2 <- string(:alphanumeric, min_length: 1, max_length: 8)
          ) do
      symbol =
        case op do
          :eq -> ":"
          :neq -> "!="
          :gt -> ">"
          :gte -> ">="
          :lt -> "<"
          :lte -> "<="
        end

      input = "#{free1} session_count#{symbol}#{amount} #{free2}"

      assert %Query{text: text, facets: [{:session_count, ^op, ^amount}]} = Query.parse(input, @facets)
      assert text == "#{free1} #{free2}"
    end
  end

  property "repeated instances of the same facet key all survive, in order" do
    check all(values <- list_of(integer(0..100), min_length: 2, max_length: 5)) do
      input = values |> Enum.map_join(" ", &"session_count:#{&1}")
      %Query{facets: facets} = Query.parse(input, @facets)

      assert facets == Enum.map(values, &{:session_count, :eq, &1})
    end
  end

  if Code.ensure_loaded?(Ash) do
    @tag :ash
    property "to_filter/1 never raises and always returns a map" do
      check all(
              key <- member_of([:a, :b, :c]),
              op <- member_of([:eq, :neq, :gt, :gte, :lt, :lte]),
              value <- one_of([integer(), string(:alphanumeric, max_length: 10), boolean()]),
              facets <- list_of(tuple({constant(key), constant(op), constant(value)}), max_length: 5)
            ) do
        filter = Query.to_filter(%Query{text: "", facets: facets})
        assert is_map(filter)
      end
    end
  end
end
