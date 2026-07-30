defmodule Flicker.Trigger do
  @moduledoc """
  The facet-entry trigger character ([Spec 024](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-024-facet-trigger-character.md)) —
  parsing and validating the `facet_trigger` attr, and answering "does this
  token open the facet menu, and for which facets".

  Without a trigger, every bare word the user types is classified
  `{:key, prefix}` and offers facet-key suggestions. That is right for a
  dedicated filter bar and wrong for a search box whose main job is free text.
  A trigger gates *discovery* on an explicit gesture: `@` opens the facet menu,
  and nothing else does.

  ## The invariant

  **A trigger is input sugar and never grammar.** `Flicker.Query.parse/2` has no
  clause for it, no token contains it, no pill displays it, and no URL carries
  it. `@stat` completes to `status:` — the trigger disappears because choosing a
  suggestion replaces the whole token, not because anything strips it.

  This is the same separation
  [ADR-013](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-013-canonical-tokens-localised-display.md)
  draws between canonical tokens and localised display, applied to input
  affordances: the affordance is configurable precisely because nothing
  persists it.

  ## Gating discovery, not recognition

  A trigger stops Flicker *offering* facet keys unprompted. It does not stop it
  understanding one that is already there: `status:active` typed out in full, or
  pasted, or restored from a URL, still classifies as a facet value against the
  whole registry. If the trigger gated recognition too, a shared search URL
  would silently stop filtering.

  ## Configuration

      facet_trigger="@"                              # one trigger, every facet
      facet_trigger={%{"@" => [:worker], "#" => [:tag]}}  # scoped, Slack-style

  A trigger must be a single grapheme, must not be whitespace, and must not be
  a character that can legally start a facet key (a letter, digit, `_` or `?`)
  — `s` as a trigger would be indistinguishable from the first letter of
  `status`. `:` **is** allowed: it is the operator, but the operator only ever
  appears *after* a key run, so a token-initial `:` is unambiguous (`:stat` is
  a trigger, `status:` is not).
  """

  alias Flicker.Facet

  @typedoc """
  Trigger grapheme to the facets it offers — `:all` for the whole registry, or
  an explicit list of facet keys.
  """
  @type t :: %{String.t() => :all | [atom()]}

  @typedoc "What a host passes as `facet_trigger`."
  @type config :: nil | String.t() | map() | keyword()

  # Exactly `Flicker.CursorContext`'s `key_char?/1` — a trigger that could
  # start a facet key would be unresolvable from the key itself.
  @key_char ~r/^[\p{L}\p{N}_?]$/u

  @doc """
  Normalises a `facet_trigger` attr into a `t/0`, or `nil` for "no trigger
  configured" (today's always-on facet suggestions).

  Raises `ArgumentError` on anything unusable rather than degrading, because a
  mistyped trigger silently disabling every facet is a far worse failure than a
  crash in dev.

  ## Examples

      iex> Flicker.Trigger.parse!(nil)
      nil

      iex> Flicker.Trigger.parse!("@")
      %{"@" => :all}

      iex> Flicker.Trigger.parse!(%{"@" => [:worker], "#" => [:tag]})
      %{"#" => [:tag], "@" => [:worker]}

      iex> Flicker.Trigger.parse!(%{})
      nil

      iex> Flicker.Trigger.parse!("@@")
      ** (ArgumentError) facet_trigger must be a single character, got: "@@"

      iex> Flicker.Trigger.parse!("s")
      ** (ArgumentError) facet_trigger cannot be a character that starts a facet key, got: "s"
  """
  @spec parse!(config()) :: t() | nil
  def parse!(nil), do: nil

  def parse!(grapheme) when is_binary(grapheme), do: %{validate!(grapheme) => :all}

  def parse!(config) when is_map(config) or is_list(config) do
    case Enum.map(config, fn {grapheme, keys} -> {validate!(grapheme), validate_keys!(keys)} end) do
      [] -> nil
      pairs -> Map.new(pairs)
    end
  end

  def parse!(other) do
    raise ArgumentError,
          "facet_trigger must be a string or a map of trigger to facet keys, got: #{inspect(other)}"
  end

  defp validate!(grapheme) when is_binary(grapheme) do
    cond do
      String.length(grapheme) != 1 ->
        raise ArgumentError, "facet_trigger must be a single character, got: #{inspect(grapheme)}"

      String.trim(grapheme) == "" ->
        raise ArgumentError, "facet_trigger cannot be whitespace"

      Regex.match?(@key_char, grapheme) ->
        raise ArgumentError,
              "facet_trigger cannot be a character that starts a facet key, got: #{inspect(grapheme)}"

      true ->
        grapheme
    end
  end

  defp validate!(other) do
    raise ArgumentError, "facet_trigger must be a string, got: #{inspect(other)}"
  end

  defp validate_keys!(:all), do: :all

  defp validate_keys!(keys) when is_list(keys) do
    if Enum.all?(keys, &is_atom/1) do
      keys
    else
      raise ArgumentError, "facet_trigger keys must be facet key atoms, got: #{inspect(keys)}"
    end
  end

  defp validate_keys!(key) when is_atom(key) and not is_nil(key), do: [key]

  defp validate_keys!(other) do
    raise ArgumentError,
          "facet_trigger keys must be a list of facet key atoms, got: #{inspect(other)}"
  end

  @doc """
  The facets `grapheme` offers, or `nil` if it isn't a configured trigger.

  `nil` is the caller's signal to treat the token as ordinary text rather than
  as facet entry — it is deliberately distinct from `[]`, which means "a
  configured trigger whose facets are all filtered out".

  ## Examples

      iex> facets = [Flicker.Facet.new(key: :worker), Flicker.Facet.new(key: :tag)]
      ...> Flicker.Trigger.scope(%{"@" => [:worker]}, "@", facets) |> Enum.map(& &1.key)
      [:worker]

      iex> facets = [Flicker.Facet.new(key: :worker)]
      ...> Flicker.Trigger.scope(%{"@" => :all}, "#", facets)
      nil
  """
  @spec scope(t() | nil, String.t(), [Facet.t()]) :: [Facet.t()] | nil
  def scope(nil, _grapheme, _facets), do: nil

  def scope(trigger, grapheme, facets) when is_map(trigger) do
    case Map.fetch(trigger, grapheme) do
      {:ok, :all} -> facets
      {:ok, keys} -> Enum.filter(facets, &(&1.key in keys))
      :error -> nil
    end
  end

  @doc """
  The configured graphemes, sorted — the list the discoverability hint renders.

  Sorted rather than in configuration order so the hint is stable across
  renders regardless of how the host's map happens to enumerate.

  ## Examples

      iex> Flicker.Trigger.graphemes(%{"@" => :all, "#" => [:tag]})
      ["#", "@"]

      iex> Flicker.Trigger.graphemes(nil)
      []
  """
  @spec graphemes(t() | nil) :: [String.t()]
  def graphemes(nil), do: []
  def graphemes(trigger) when is_map(trigger), do: trigger |> Map.keys() |> Enum.sort()
end
