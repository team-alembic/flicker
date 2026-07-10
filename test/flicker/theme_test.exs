defmodule Flicker.ThemeTest do
  # Mutates the global `:flicker, :default_theme` Application env — not
  # safe to run concurrently with other tests that read it.
  use ExUnit.Case, async: false

  alias Flicker.Theme

  @parts Theme.vanilla() |> Map.from_struct() |> Map.keys() |> Enum.sort()

  @presets %{
    vanilla: Theme.vanilla(),
    tailwind: Theme.tailwind(),
    daisy_ui: Theme.daisy_ui()
  }

  describe "presets" do
    test "every preset covers every theme part key with a non-empty class string" do
      for {name, preset} <- @presets do
        values = Map.from_struct(preset)

        assert Map.keys(values) |> Enum.sort() == @parts,
               "#{name} does not cover exactly the parts in Flicker.Theme's struct"

        for part <- @parts do
          value = Map.fetch!(values, part)
          assert is_binary(value) and value != "", "#{name} is missing a class for #{part}"
        end
      end
    end

    test "presets are distinct from one another" do
      classes = Enum.map(@presets, fn {_name, preset} -> Map.from_struct(preset) end)

      assert classes |> Enum.uniq() |> length() == map_size(@presets)
    end
  end

  describe "resolve/1" do
    test "defaults to vanilla with no override or config" do
      assert Theme.resolve() == Theme.vanilla()
    end

    test "config :flicker, :default_theme overrides vanilla" do
      Application.put_env(:flicker, :default_theme, Theme.tailwind())
      on_exit(fn -> Application.delete_env(:flicker, :default_theme) end)

      assert Theme.resolve() == Theme.tailwind()
    end

    test "a per-component override takes precedence over config" do
      Application.put_env(:flicker, :default_theme, Theme.tailwind())
      on_exit(fn -> Application.delete_env(:flicker, :default_theme) end)

      assert Theme.resolve(Theme.daisy_ui()) == Theme.daisy_ui()
    end

    test "a partial map override merges onto the base" do
      resolved = Theme.resolve(%{search_input: "my-input"})

      assert resolved.search_input == "my-input"
      assert resolved.listbox == Theme.vanilla().listbox
    end
  end
end
