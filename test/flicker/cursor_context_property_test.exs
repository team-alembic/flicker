defmodule Flicker.CursorContextPropertyTest do
  @moduledoc """
  Property-tests `Flicker.CursorContext.classify/3` for total coverage — per
  Spec 003's cursor-context acceptance criterion, it must never raise and
  must always classify, for arbitrary input, arbitrary cursor position
  (including out-of-range), and arbitrary facet configuration.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Flicker.CursorContext
  alias Flicker.Facet

  @facets [
    %Facet{key: :status, type: :enum, values: [:active, :inactive]},
    %Facet{key: :worker},
    %Facet{key: :after, type: :date, default_op: :gte, operators: [:gte, :lt]},
    %Facet{key: :session_count, type: :integer, operators: [:eq, :neq, :gt, :gte, :lt, :lte]}
  ]

  defp any_char do
    one_of([
      string(:alphanumeric, length: 1),
      member_of(~w[: > < ! = " \\ \s \t \n a b 7 é 😀 _ ? -])
    ])
  end

  defp adversarial_input do
    map(list_of(any_char(), max_length: 60), &Enum.join/1)
  end

  defp valid_state?({:key, prefix}), do: is_binary(prefix)
  defp valid_state?({:value, %Facet{}, prefix}), do: is_binary(prefix)
  defp valid_state?(:text), do: true
  defp valid_state?(_other), do: false

  property "never raises and always classifies, for arbitrary strings built from grammar-relevant characters" do
    check all(
            input <- adversarial_input(),
            cursor <- integer(0..70)
          ) do
      assert valid_state?(CursorContext.classify(input, cursor, @facets))
    end
  end

  property "never raises and always classifies, for fully arbitrary Unicode binaries" do
    check all(
            input <- string(:utf8, max_length: 200),
            cursor <- integer(-10..250)
          ) do
      assert valid_state?(CursorContext.classify(input, cursor, @facets))
    end
  end

  property "never raises for a cursor wildly out of range in either direction" do
    check all(
            input <- adversarial_input(),
            cursor <- one_of([integer(-1_000_000..-1), integer(1_000_000..2_000_000)])
          ) do
      assert valid_state?(CursorContext.classify(input, cursor, @facets))
    end
  end

  property "never raises with no facets registered at all" do
    check all(
            input <- adversarial_input(),
            cursor <- integer(0..70)
          ) do
      assert valid_state?(CursorContext.classify(input, cursor, []))
    end
  end

  property "the cursor never lands outside the classified prefix's own length bound" do
    check all(
            input <- string(:alphanumeric, max_length: 40),
            cursor <- integer(0..40)
          ) do
      clamped = cursor |> max(0) |> min(String.length(input))

      case CursorContext.classify(input, clamped, @facets) do
        {:key, prefix} -> assert String.length(prefix) <= clamped
        {:value, _facet, prefix} -> assert String.length(prefix) <= clamped
        :text -> :ok
      end
    end
  end

  property "classifying at cursor 0 is always key context with an empty prefix" do
    check all(input <- adversarial_input()) do
      assert CursorContext.classify(input, 0, @facets) == {:key, ""}
    end
  end
end
