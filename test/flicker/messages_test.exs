defmodule Flicker.MessagesTest do
  # Mutates the global `:flicker, :messages` Application env — not safe to
  # run concurrently with other tests that read it.
  use ExUnit.Case, async: false

  alias Flicker.Messages

  defmodule FrenchSearchOnly do
    @moduledoc false
    @behaviour Flicker.Messages

    @impl true
    def message(:search_placeholder, _bindings), do: "Rechercher..."
    def message(key, bindings), do: Flicker.Messages.English.message(key, bindings)
  end

  describe "resolve/1" do
    test "defaults to Flicker.Messages.English with no override or config" do
      assert Messages.resolve() == Flicker.Messages.English
    end

    test "config :flicker, :messages overrides the default" do
      Application.put_env(:flicker, :messages, FrenchSearchOnly)
      on_exit(fn -> Application.delete_env(:flicker, :messages) end)

      assert Messages.resolve() == FrenchSearchOnly
    end

    test "a per-component override takes precedence over config" do
      Application.put_env(:flicker, :messages, FrenchSearchOnly)
      on_exit(fn -> Application.delete_env(:flicker, :messages) end)

      assert Messages.resolve(Flicker.Messages.English) == Flicker.Messages.English
    end
  end

  describe "get/3" do
    test "looks up a key through the resolved module" do
      assert Messages.get(FrenchSearchOnly, :search_placeholder) == "Rechercher..."
    end

    test "falls back to English for a key the override doesn't implement" do
      assert Messages.get(FrenchSearchOnly, :no_results) == "No results found"
    end

    test "interpolates bindings" do
      assert Messages.get(nil, :results_count, %{count: 5}) == "5 results available"
    end
  end

  describe "Flicker.Messages.English" do
    test "every key documented in the moduledoc has a clause" do
      keys = [
        :search_placeholder,
        :loading,
        :no_results,
        :error,
        :keep_typing,
        :clear_selection
      ]

      for key <- keys do
        assert is_binary(Flicker.Messages.English.message(key, %{}))
      end

      assert is_binary(Flicker.Messages.English.message(:min_chars_hint, %{min_chars: 3}))
      assert is_binary(Flicker.Messages.English.message(:results_count, %{count: 0}))
      assert is_binary(Flicker.Messages.English.message(:keyboard_shortcut_hint, %{chord: "Mod+K"}))
    end
  end

  describe "validation reason coverage (Spec 018 / ADR-012)" do
    test "every reason Flicker.Facet.Cast can produce renders a non-empty message" do
      # Swept off `reasons/0` rather than hardcoded, so a new reason with no
      # message fails here instead of rendering an empty error to a user.
      params = %{values: [:active, :inactive], min: 0, max: 500, message: "nope", value: "x"}

      for reason <- Flicker.Facet.Cast.reasons() do
        key = Flicker.Facet.Cast.message_key(reason)
        message = Flicker.Messages.get(nil, key, params)

        assert is_binary(message) and message != "",
               "reason #{inspect(reason)} (key #{inspect(key)}) rendered #{inspect(message)}"
      end
    end

    test "an unknown reason falls back to a generic message rather than crashing" do
      key = Flicker.Facet.Cast.message_key(:invented_by_a_host)

      assert key == :invalid_value
      assert Flicker.Messages.get(nil, key, %{}) == "is not valid"
    end

    test "out_of_bounds reads correctly for one-sided bounds" do
      assert Flicker.Messages.get(nil, :invalid_out_of_bounds, %{min: nil, max: 5}) == "must be at most 5"
      assert Flicker.Messages.get(nil, :invalid_out_of_bounds, %{min: 5, max: nil}) == "must be at least 5"
    end

    test "not_in_values names the allowed set" do
      assert Flicker.Messages.get(nil, :invalid_not_in_values, %{values: [:a, :b]}) == "must be one of: a, b"
    end
  end
end
