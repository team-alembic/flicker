defmodule Flicker.Keyboard do
  @moduledoc """
  Server-side chord parsing/validation for `activate_with_keyboard`
  (Spec 006).

  A chord string is `+`-separated modifiers (`meta`, `ctrl`, `alt`,
  `shift`, or the portable alias `mod`) followed by exactly one key, e.g.
  `"mod+k"` or `"ctrl+shift+a"`. Validation happens once, at
  `Flicker.select/1` render time, so a misconfigured attr fails loudly at
  the call site rather than silently doing nothing in the browser.

  `mod` is deliberately left unresolved here — it becomes `meta` on macOS
  and `ctrl` elsewhere, a decision the colocated hook makes client-side
  (ADR-007) because the server can't reliably know the requesting
  platform. `aria_keyshortcuts/1` sidesteps the same problem by emitting
  both alternatives.
  """

  @modifiers ~w(meta ctrl alt shift mod)

  @typedoc "A validated chord: its modifier list (as given, `mod` unresolved) and trailing key."
  @type t :: %{modifiers: [String.t()], key: String.t()}

  @doc """
  Parses and validates a chord string.

  Returns `{:ok, chord}` for a syntactically valid chord — at least one
  recognised modifier, followed by exactly one key that isn't itself a
  modifier name — or `{:error, reason}` describing what's wrong. Bare-key
  chords (no modifier, e.g. `"k"`) are always rejected: activating on a
  plain keypress anywhere in the document would hijack ordinary typing.
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(chord) when is_binary(chord) do
    parts = chord |> String.split("+") |> Enum.map(&String.trim/1)

    cond do
      chord == "" ->
        {:error, "activate_with_keyboard chord cannot be blank"}

      Enum.any?(parts, &(&1 == "")) ->
        {:error, "activate_with_keyboard chord #{inspect(chord)} has an empty segment (check for a stray \"+\")"}

      length(parts) < 2 ->
        {:error, bare_key_error(chord)}

      true ->
        {modifiers, [key]} = Enum.split(parts, -1)
        validate_chord(chord, modifiers, key)
    end
  end

  @doc "Like `parse/1`, raising `ArgumentError` with a clear message on an invalid chord."
  @spec validate!(String.t()) :: t()
  def validate!(chord) do
    case parse(chord) do
      {:ok, parsed} -> parsed
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Formats a validated chord as an `aria-keyshortcuts` value.

  Emits space-separated alternatives so `"mod+k"` yields both platform
  forms — `"Meta+K Control+K"` — per the
  [WAI-ARIA spec](https://www.w3.org/TR/wai-aria-1.1/#aria-keyshortcuts),
  since the server can't know which one the visiting browser will resolve
  `mod` to.
  """
  @spec aria_keyshortcuts(t()) :: String.t()
  def aria_keyshortcuts(%{modifiers: modifiers, key: key}) do
    modifiers
    |> expand_mod()
    |> Enum.map_join(" ", &format_aria_alternative(&1, key))
  end

  @doc """
  A platform-neutral display string for the kbd hint, e.g. `"Mod+K"`.

  Shown until the colocated hook's `mounted` callback replaces it with
  platform-formatted text (`⌘K` on macOS, `Ctrl+K` elsewhere) — this
  function never itself guesses the platform.
  """
  @spec display(t()) :: String.t()
  def display(%{modifiers: modifiers, key: key}) do
    (Enum.map(modifiers, &String.capitalize/1) ++ [String.upcase(key)])
    |> Enum.join("+")
  end

  defp validate_chord(chord, modifiers, key) do
    invalid_modifiers = Enum.reject(modifiers, &(&1 in @modifiers))

    cond do
      invalid_modifiers != [] ->
        {:error,
         "activate_with_keyboard chord #{inspect(chord)} has unknown modifier(s) " <>
           "#{inspect(invalid_modifiers)} — valid modifiers are #{inspect(@modifiers)}"}

      key in @modifiers ->
        {:error,
         "activate_with_keyboard chord #{inspect(chord)} is missing a trailing key (it ends in a modifier name)"}

      true ->
        {:ok, %{modifiers: modifiers, key: key}}
    end
  end

  defp bare_key_error(chord) do
    "activate_with_keyboard chord #{inspect(chord)} has no modifier — bare-key chords are " <>
      "rejected (matching on a plain keypress anywhere in the document would hijack ordinary " <>
      "typing); did you mean #{inspect("mod+" <> chord)}?"
  end

  defp expand_mod(modifiers) do
    if "mod" in modifiers do
      without_mod = Enum.reject(modifiers, &(&1 == "mod"))
      [without_mod ++ ["meta"], without_mod ++ ["ctrl"]]
    else
      [modifiers]
    end
  end

  defp format_aria_alternative(modifiers, key) do
    (Enum.map(modifiers, &aria_modifier_name/1) ++ [aria_key_name(key)])
    |> Enum.join("+")
  end

  defp aria_modifier_name("meta"), do: "Meta"
  defp aria_modifier_name("ctrl"), do: "Control"
  defp aria_modifier_name("alt"), do: "Alt"
  defp aria_modifier_name("shift"), do: "Shift"

  defp aria_key_name(key) when byte_size(key) == 1, do: String.upcase(key)
  defp aria_key_name(key), do: key
end
