defmodule Flicker.KeyboardTest do
  @moduledoc """
  Covers `Flicker.Keyboard`'s server-side chord validation and formatting
  (Spec 006) — the parts checkable without a browser. Actual chord
  *matching* (a live `KeyboardEvent`, the `mod` alias resolving to the
  visiting platform, and the duplicate-chord console warning) is pure
  client-side JS in the colocated hook's `registerChord`/`activateChord`
  and isn't reachable from ExUnit (PhoenixTest doesn't run JavaScript) —
  see the manual/browser-testing note in `Flicker.SelectKeyboardActivationTest`.
  """

  use ExUnit.Case, async: true

  alias Flicker.Keyboard

  describe "parse/1" do
    test "accepts a mod chord" do
      assert Keyboard.parse("mod+k") == {:ok, %{modifiers: ["mod"], key: "k"}}
    end

    test "accepts multiple modifiers" do
      assert Keyboard.parse("ctrl+shift+a") == {:ok, %{modifiers: ["ctrl", "shift"], key: "a"}}
    end

    test "rejects a bare key with a loud, explanatory error" do
      assert {:error, reason} = Keyboard.parse("k")
      assert reason =~ "no modifier"
      assert reason =~ "bare-key"
      assert reason =~ "mod+k"
    end

    test "rejects a blank chord" do
      assert {:error, reason} = Keyboard.parse("")
      assert reason =~ "blank"
    end

    test "rejects an unknown modifier" do
      assert {:error, reason} = Keyboard.parse("cmd+k")
      assert reason =~ "unknown modifier"
      assert reason =~ ~s(["cmd"])
    end

    test "rejects a chord with no trailing key" do
      assert {:error, reason} = Keyboard.parse("ctrl+shift")
      assert reason =~ "missing a trailing key"
    end

    test "rejects a chord with a stray separator" do
      assert {:error, reason} = Keyboard.parse("mod++k")
      assert reason =~ "empty segment"
    end
  end

  describe "validate!/1" do
    test "returns the parsed chord for valid input" do
      assert Keyboard.validate!("mod+k") == %{modifiers: ["mod"], key: "k"}
    end

    test "raises ArgumentError for invalid input" do
      assert_raise ArgumentError, ~r/bare-key/, fn -> Keyboard.validate!("k") end
    end
  end

  describe "aria_keyshortcuts/1" do
    test "expands mod into both platform alternatives" do
      chord = Keyboard.validate!("mod+k")
      assert Keyboard.aria_keyshortcuts(chord) == "Meta+K Control+K"
    end

    test "formats a chord with no mod alias as a single alternative" do
      chord = Keyboard.validate!("ctrl+shift+a")
      assert Keyboard.aria_keyshortcuts(chord) == "Control+Shift+A"
    end
  end

  describe "display/1" do
    test "formats a platform-neutral hint string" do
      chord = Keyboard.validate!("mod+k")
      assert Keyboard.display(chord) == "Mod+K"
    end

    test "capitalizes every modifier" do
      chord = Keyboard.validate!("ctrl+shift+a")
      assert Keyboard.display(chord) == "Ctrl+Shift+A"
    end
  end
end
