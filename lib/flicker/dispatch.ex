defmodule Flicker.Dispatch do
  @moduledoc """
  Dispatch-policy decisions ([Spec 020](https://github.com/team-alembic/flicker/blob/main/docs/specs/spec-020-query-dispatch-policy.md)) —
  when a component should actually run a query, and what to render while it
  isn't.

  Two of the three concerns a dispatch policy would normally own are already
  handled below the component, and this module deliberately does not
  reimplement either:

    * **Debouncing** is `phx-debounce` on the input — client-side, so a
      coalesced keystroke never reaches the server at all. This module only
      decides *what value that attribute takes* (`debounce_attr/2`).
    * **Request supersession** is `Phoenix.LiveView.start_async/3` keyed on
      the same name: a slow response for an earlier keystroke is discarded by
      LiveView itself (see `Flicker.SelectStaleResultsTest`). Nothing here
      tracks sequence numbers.

  What is left is a handful of pure decisions: whether a given trigger
  dispatches at all under the active policy, whether there is undispatched
  text (the `:enter` policy's "press Enter to search" affordance), and which
  empty state — if any — an empty result list should render as. Every
  function is a pure function of its arguments, so the whole policy is
  unit-testable with no LiveView, no provider, and no browser.

  ## Policies

    * `:debounce` (default) — dispatch `debounce` ms after the last
      keystroke. Today's behaviour, unchanged.
    * `:immediate` — dispatch on every keystroke; `phx-debounce` is omitted
      entirely. For a `Flicker.Providers.Static` or other in-memory provider,
      where a round trip costs nothing and 150ms is pure latency.
    * `:enter` — typing dispatches nothing; only `Enter` (and facet commits,
      and the initial listing) do. For an expensive or metered backend.

  ## Triggers

    * `:input` — the user typed. The only trigger any policy suppresses.
    * `:enter` — the user pressed Enter.
    * `:facet_commit` — a facet was committed or removed. A deliberate,
      discrete act, so it always dispatches
      ([ADR-011](https://github.com/team-alembic/flicker/blob/main/docs/adrs/adr-011-facet-editors-are-modal-subcontexts.md)).
    * `:initial` — the picker opened. Always dispatches, under every policy:
      opening a picker and seeing nothing until you press Enter is
      indefensible.
  """

  @typedoc "When a query is allowed to run."
  @type policy :: :debounce | :immediate | :enter

  @typedoc "What is asking for a dispatch."
  @type trigger :: :input | :enter | :facet_commit | :initial

  @typedoc "Which empty state an empty result list should render as."
  @type empty_state :: :none | :no_results | :below_min_length | :listing

  @policies [:debounce, :immediate, :enter]

  @doc """
  The known policies, in documentation order — the single source of truth
  for the `:dispatch` attr's validation and for tests that sweep every
  policy.

  ## Examples

      iex> Flicker.Dispatch.policies()
      [:debounce, :immediate, :enter]
  """
  @spec policies() :: [policy()]
  def policies, do: @policies

  @doc """
  Whether `trigger` should dispatch a query under `policy`, given the typed
  free text and the configured `min_length`.

  `:facet_commit` and `:initial` always dispatch — a committed facet is a
  deliberate act, and the open-with-no-input listing is not a search. Only
  `:input` is suppressed by a policy, and only `:input`/`:enter` are gated by
  `min_length`.

  Blank text always dispatches: it is the listing state, not a one-character
  search, so `min_length` does not withhold it. That distinction is what lets
  clearing the input return to the listing rather than to "no results".

  ## Examples

      iex> Flicker.Dispatch.dispatch?(:debounce, :input, "cas", 0)
      true

      iex> Flicker.Dispatch.dispatch?(:enter, :input, "cas", 0)
      false

      iex> Flicker.Dispatch.dispatch?(:enter, :enter, "cas", 0)
      true

      iex> Flicker.Dispatch.dispatch?(:enter, :facet_commit, "cas", 0)
      true

      iex> Flicker.Dispatch.dispatch?(:debounce, :input, "c", 2)
      false

      iex> Flicker.Dispatch.dispatch?(:debounce, :input, "", 2)
      true

      iex> Flicker.Dispatch.dispatch?(:enter, :initial, "", 2)
      true
  """
  @spec dispatch?(policy(), trigger(), String.t(), non_neg_integer()) :: boolean()
  def dispatch?(_policy, trigger, _text, _min_length) when trigger in [:facet_commit, :initial], do: true

  def dispatch?(:enter, :input, _text, _min_length), do: false

  def dispatch?(policy, trigger, text, min_length) when policy in @policies and trigger in [:input, :enter] do
    long_enough?(text, min_length)
  end

  defp long_enough?("", _min_length), do: true
  defp long_enough?(text, min_length), do: String.length(text) >= min_length

  @doc """
  The value for the input's `phx-debounce` attribute under `policy`, or `nil`
  to omit the attribute entirely.

  Only `:debounce` debounces. `:immediate` wants every keystroke, and
  `:enter` suppresses keystroke dispatch in the component anyway — leaving a
  debounce on either would add latency to no purpose.

  ## Examples

      iex> Flicker.Dispatch.debounce_attr(:debounce, 150)
      150

      iex> Flicker.Dispatch.debounce_attr(:immediate, 150)
      nil

      iex> Flicker.Dispatch.debounce_attr(:enter, 150)
      nil
  """
  @spec debounce_attr(policy(), non_neg_integer()) :: non_neg_integer() | nil
  def debounce_attr(:debounce, debounce_ms), do: debounce_ms
  def debounce_attr(policy, _debounce_ms) when policy in @policies, do: nil

  @doc """
  Whether there is typed text that hasn't been dispatched yet — what drives
  the `:enter` policy's "press Enter to search" affordance and its
  `aria-describedby` hint.

  Always `false` for the dispatching policies: under `:debounce` and
  `:immediate` any divergence is a debounce window's worth of milliseconds,
  and flashing a hint for 150ms would be worse than no hint at all.

  ## Examples

      iex> Flicker.Dispatch.pending?(:enter, "casey", "")
      true

      iex> Flicker.Dispatch.pending?(:enter, "casey", "casey")
      false

      iex> Flicker.Dispatch.pending?(:debounce, "casey", "")
      false
  """
  @spec pending?(policy(), String.t(), String.t()) :: boolean()
  def pending?(:enter, text, dispatched_text), do: text != dispatched_text
  def pending?(policy, _text, _dispatched_text) when policy in @policies, do: false

  @doc """
  Which empty state an empty `results` list should render as — or `:none`
  when nothing empty-ish should render at all.

  "No results" is a claim about the data, and it must only be made about a
  *settled* empty response. Rendering it while a request is in flight, or for
  a query that was never dispatched because it was below `min_length`, tells
  the user something false about their data.

    * `:none` — there are results, or a request is in flight. Render the list.
    * `:below_min_length` — text is typed but shorter than `min_length`, so
      nothing was dispatched. Prompt for more characters.
    * `:listing` — nothing typed and nothing to show: the provider's default
      listing is genuinely empty.
    * `:no_results` — a dispatched search settled with nothing. The only case
      that may say "no results".

  ## Examples

      iex> Flicker.Dispatch.empty_state(false, "cas", 0, [%Flicker.Result{value: 1, label: "Casey"}])
      :none

      iex> Flicker.Dispatch.empty_state(true, "cas", 0, [])
      :none

      iex> Flicker.Dispatch.empty_state(false, "c", 2, [])
      :below_min_length

      iex> Flicker.Dispatch.empty_state(false, "", 0, [])
      :listing

      iex> Flicker.Dispatch.empty_state(false, "cas", 0, [])
      :no_results
  """
  @spec empty_state(boolean(), String.t(), non_neg_integer(), list()) :: empty_state()
  def empty_state(_loading?, _text, _min_length, [_ | _]), do: :none
  def empty_state(true, _text, _min_length, []), do: :none
  def empty_state(false, "", _min_length, []), do: :listing

  def empty_state(false, text, min_length, []) do
    if long_enough?(text, min_length), do: :no_results, else: :below_min_length
  end
end
