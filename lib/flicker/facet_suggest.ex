defmodule Flicker.FacetSuggest do
  @moduledoc """
  Shared facet-suggestion machinery ([Spec 003](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-003-faceted-search.md)) —
  the pure functions both `Flicker.search/1` and the `facets` attr on
  `Flicker.select/1` call to turn a `Flicker.CursorContext` classification
  into a suggestion list, and to splice a chosen suggestion back into the
  typed text.

  This is the "same machinery" the spec calls for: neither component
  reimplements key/value suggestion filtering or token replacement, they
  both drive this module off `Flicker.CursorContext.classify/3`.

  Every suggestion is a `Flicker.Result` — reusing the same display struct
  the record-search listbox already renders — tagged
  `meta: %{flicker_facet: true, insert: text}`: `:insert` is the literal
  text that replaces the current token when the suggestion is chosen
  (`"status:"` for a key suggestion, `"status:active "` for a value one).
  A caller distinguishes a facet suggestion from an ordinary record result
  by checking `result.meta[:flicker_facet]`.
  """

  alias Flicker.{CursorContext, Facet, Result}

  @typedoc "A facet suggestion — a `Flicker.Result` tagged for token insertion."
  @type suggestion :: Result.t()

  @doc """
  Classifies `text` (cursor assumed at the end — see moduledoc note below)
  against `facets`.

  Both components track the cursor as "end of the typed text": Flicker
  wires plain `phx-keyup`/`phx-change` payloads (no `selectionStart`), so
  mid-token editing (moving the cursor back into an already-typed token)
  isn't distinguished from typing at the end — `Flicker.CursorContext`
  itself supports arbitrary cursor positions and is exercised at every
  position by its own unit/property tests; this is a component-wiring
  simplification, not a limitation of the state machine.
  """
  @spec classify(String.t(), [Facet.t()]) :: CursorContext.t()
  def classify(text, facets), do: CursorContext.classify(text, String.length(text), facets)

  @doc """
  Facet-key suggestions matching `prefix` — 'stat' → 'status:'.

  Filters `facets` to those whose key starts with `prefix` (case-sensitive,
  matching how facet keys are typed) and maps each to a suggestion whose
  `:insert` is `"<key>:"` — landing the cursor right after the operator, so
  the very next classification is `{:value, facet, ""}`.
  """
  @spec key_suggestions(String.t(), [Facet.t()]) :: [suggestion()]
  def key_suggestions(prefix, facets) do
    facets
    |> Enum.filter(&String.starts_with?(Atom.to_string(&1.key), prefix))
    |> Enum.map(&key_suggestion/1)
  end

  defp key_suggestion(facet) do
    key_text = "#{facet.key}:"

    %Result{
      value: key_text,
      label: key_text,
      sublabel: facet.label,
      meta: %{flicker_facet: true, insert: key_text}
    }
  end

  @doc """
  Value suggestions for `facet`'s closed value set, filtered by `prefix`.

  Two facet types have a closed set to suggest from (Spec 003's type
  table):

    * `:enum` — the picklist in `:values`, filtered by `prefix` against the
      value's own key or label (case-insensitive substring).
    * `:boolean` — the fixed pair `true` / `false`, filtered by `prefix`
      (case-insensitive) against each literal's own text — `"f"` suggests
      only `false`.

  Returns `[]` for any other facet type — a plain string/numeric/date
  facet has no closed picklist (a relationship facet's values come from
  `related_search/4` instead).
  """
  @spec enum_value_suggestions(Facet.t(), String.t()) :: [suggestion()]
  def enum_value_suggestions(%Facet{type: :enum, values: values, value_labels: value_labels, key: key}, prefix) do
    downcased_prefix = String.downcase(prefix)

    values
    |> Enum.filter(&value_matches?(&1, value_labels, downcased_prefix))
    |> Enum.map(&enum_suggestion(key, &1, value_labels))
  end

  def enum_value_suggestions(%Facet{type: :boolean, key: key}, prefix) do
    downcased_prefix = String.downcase(prefix)

    [true, false]
    |> Enum.filter(&String.starts_with?(to_string(&1), downcased_prefix))
    |> Enum.map(&boolean_suggestion(key, &1))
  end

  def enum_value_suggestions(_facet, _prefix), do: []

  defp boolean_suggestion(key, value) do
    label = to_string(value)
    insert = "#{key}:#{label} "

    %Result{
      value: "#{key}:#{label}",
      label: label,
      sublabel: nil,
      meta: %{flicker_facet: true, insert: insert}
    }
  end

  defp value_matches?(value, value_labels, downcased_prefix) do
    label = Map.get(value_labels || %{}, value, to_string(value))

    String.contains?(String.downcase(label), downcased_prefix) or
      String.contains?(String.downcase(to_string(value)), downcased_prefix)
  end

  defp enum_suggestion(key, value, value_labels) do
    label = Map.get(value_labels || %{}, value, to_string(value))
    insert = "#{key}:#{quote_if_needed(to_string(value))} "

    %Result{
      value: "#{key}:#{value}",
      label: label,
      sublabel: nil,
      meta: %{flicker_facet: true, insert: insert}
    }
  end

  if Code.ensure_loaded?(Ash) do
    alias Flicker.{Provider, Query}

    @doc """
    Runs the nested, actor-scoped search for a relationship facet's values
    (Spec 003) — a plain `Flicker.Providers.AshResource` search over
    `facet.related.resource`, filtered by `prefix`, honouring `actor` and
    `tenant` (ADR-004): a record the actor can't read never appears as a
    facet-value suggestion.

    Only compiles when `ash` is present (ADR-006) — a relationship facet's
    `:related` is itself an Ash-only concept.
    """
    @spec related_search(Facet.t(), String.t(), keyword()) ::
            {:ok, [suggestion()]} | {:error, term()}
    def related_search(%Facet{related: %{resource: resource} = related, key: key}, prefix, opts) do
      provider =
        {Flicker.Providers.AshResource, resource: resource, search: related.search, option_label: related.option_label}

      with {:ok, results} <- Provider.run_search(provider, %Query{text: prefix}, opts) do
        {:ok, Enum.map(results, &related_suggestion(key, &1))}
      end
    end

    defp related_suggestion(key, %Result{value: value, label: label}) do
      insert = "#{key}:#{quote_if_needed(to_string(value))} "

      %Result{
        value: label,
        label: label,
        sublabel: nil,
        meta: %{flicker_facet: true, insert: insert}
      }
    end
  end

  defp quote_if_needed(value) do
    if String.contains?(value, [" ", "\""]) do
      ~s("#{String.replace(value, "\"", "\\\"")}")
    else
      value
    end
  end

  @doc """
  Splices `replacement` in for the current token, assuming the cursor sits
  at the end of `text` (see `classify/2`) — the current token boundary is
  found the same quote-aware way `CursorContext.classify/3` finds it
  (`CursorContext.token_start/2`), so a token that is a double-quoted span
  containing whitespace (`worker:"Casey N`) is replaced whole rather than
  just its trailing word.

  ## Examples

      iex> Flicker.FacetSuggest.replace_current_token("status:acti", "status:active ")
      "status:active "

      iex> Flicker.FacetSuggest.replace_current_token("foo bar stat", "status:")
      "foo bar status:"

      iex> Flicker.FacetSuggest.replace_current_token(~s(worker:"Casey N), "worker:123 ")
      "worker:123 "
  """
  @spec replace_current_token(String.t(), String.t()) :: String.t()
  def replace_current_token(text, replacement) do
    start = CursorContext.token_start(text, String.length(text))
    String.slice(text, 0, start) <> replacement
  end

  @doc """
  Resolves the facet registry `Flicker.select/1`'s `facets:` attr and
  `Flicker.search/1` share.

  Precedence:

    * `resource:` set (Tier 1) — `facets:` is a list of bare keys /
      `{key, overrides}` pairs, expanded by
      `Flicker.Providers.AshResource.facets/1`.
    * `source:` set (Tier 2) to a provider that implements the optional
      `c:Flicker.Provider.facets/0` callback — that provider's own facet
      registry.
    * `facets:` already a list of `Flicker.Facet` structs — used as-is (a
      hand-built registry, no resource/provider introspection).
    * anything else — `[]` (no facets configured).
  """
  @spec resolve_facets(map()) :: [Facet.t()]

  # Explicit `%Facet{}` structs always win, even alongside `resource:` — a
  # caller who builds their own registry by hand is opting out of Ash
  # derivation for it, so this clause must be checked before the `resource:`
  # one below (clause order matters here: matching is top-to-bottom).
  # Without this precedence, `%{resource: resource, facets: [%Facet{} | _]}`
  # would be sent into `AshResource.facets/1`, which expects atom specs /
  # `{key, overrides}` pairs, not already-built structs, and can crash.
  def resolve_facets(%{facets: [%Facet{} | _] = facets}), do: facets

  # `resource:` (Tier 1) is itself an Ash-only concept — `AshResource.facets/1`
  # only compiles when `ash` is present (ADR-006). Without `ash`, this clause
  # doesn't exist at all, so a `resource:` assign falls through to the plain
  # `[]` clause below instead of referencing an undefined function.
  if Code.ensure_loaded?(Ash) do
    def resolve_facets(%{resource: resource, facets: facets}) when not is_nil(resource) do
      Flicker.Providers.AshResource.facets(resource: resource, facets: facets || [])
    end
  end

  def resolve_facets(%{source: {module, _opts}}) when is_atom(module) do
    provider_facets(module)
  end

  def resolve_facets(%{source: module}) when is_atom(module) and not is_nil(module) do
    provider_facets(module)
  end

  def resolve_facets(_assigns), do: []

  defp provider_facets(module) do
    if function_exported?(module, :facets, 0), do: module.facets(), else: []
  end
end
