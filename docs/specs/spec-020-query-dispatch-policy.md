---
status: draft # draft | ready | in-progress | shipped
date: 2026-07-28
depends_on: [spec-003, spec-010, adr-011, adr-012]
---

# Spec 020: Query dispatch policy — when the search actually runs

Dispatch is *already* partly solved, and this spec was originally drafted on a
wrong premise. Two of the three things it set out to add already exist:

- **Debounce.** `debounce` is a public attr on every component, defaulting to
  150ms, implemented as `phx-debounce` on the input. That is client-side: a
  coalesced keystroke never reaches the server at all, which is strictly better
  than any server-side timer this spec could add.
- **Request supersession.** `start_async/3` keyed on `:search` gives
  last-write-wins for free — a slow response for an earlier keystroke is
  discarded by LiveView itself, proven by
  [`select_stale_results_test.exs`](../../test/flicker/select_stale_results_test.exs).

So this spec is narrower than first drafted, and the remaining gaps are the
*perceptual* ones — the difference between a picker that feels instant and one
that feels nervous:

- No way to turn debounce off (`:immediate`) or to require `Enter` (`:enter`) for
  an expensive or metered backend.
- A spinner appears for a 40ms query, which reads as *slower* than no spinner.
- Previous results are retained while the next query runs, but nothing marks them
  as stale, so a changed list looks settled when it isn't.

Two further things this spec originally claimed to add are also already shipped,
and it must not duplicate them:

- **Minimum query length** is the existing `min_chars` attr, complete with a
  `:min_chars_hint` message and its own empty state. This spec uses that name
  rather than introducing `min_length` as a synonym.
- **Empty-state honesty** — `Flicker.Components.Select` already gates "no
  results" on `!@loading`, so it never renders mid-flight. This spec consolidates
  the scattered predicates behind one decision function rather than changing the
  behaviour.

## Scope

### New attrs (on `Flicker.search`, `Flicker.select`, `Flicker.palette`)

```elixir
attr :dispatch, :atom, default: :debounce   # :debounce | :immediate | :enter
attr :debounce, :integer, default: 150      # EXISTS — ms, when dispatch: :debounce
attr :min_length, :integer, default: 0      # free-text chars before dispatching
attr :loading_delay, :integer, default: 200 # ms before any loading affordance
```

- **`:debounce`** (default) — today's behaviour, unchanged: `phx-debounce` at the
  `debounce` value. 150ms is below the ~200ms threshold at which an interface
  stops feeling instant, while still collapsing a burst of typing into one query.
- **`:immediate`** — omits `phx-debounce` entirely, so every keystroke dispatches.
  Correct for a `Static` provider or an in-memory list, where a round-trip costs
  nothing and 150ms is pure latency.
- **`:enter`** — dispatch only on `Enter` (and on facet commit, and on
  clear/remove). For expensive or metered backends. The component makes the
  pending state obvious: the input carries a "press Enter to search" affordance
  and `aria-describedby` says so, because a search box that silently doesn't
  search is a broken search box.

**Facet commits always dispatch immediately, under every policy.** Choosing a
value from a set, committing a date range, toggling a switch, or removing a pill
is a deliberate, discrete act — debouncing or deferring it would be wrong.
Per [ADR-011](../adrs/adr-011-facet-editors-are-modal-subcontexts.md) nothing
dispatches while an editor is open, and the commit is the one dispatch.

Free-text typing is the only thing any policy applies to.

### In-flight correctness (all policies, not configurable)

These are not options. A picker that gets them wrong is broken regardless of
policy:

- **Request supersession — already provided.** `start_async/3` keyed on `:search`
  discards a superseded task's result. This spec adds no sequence numbers; it
  documents the existing guarantee and extends the same keying to any new async
  work (Spec 021's counts, Spec 022's recent-value resolution) so they inherit it
  rather than reinventing it.
- **Coalescing — already provided**, by the same mechanism plus `phx-debounce`.
- **Stale-while-revalidate.** The previous result set stays rendered, dimmed via
  a theme part, while the next is in flight. The list never empties and then
  refills — no layout jump, no flash.
- **Loading affordance delay.** No spinner, skeleton, or dimming for the first
  `loading_delay` ms. A 60ms query that flashes a spinner reads as *slower* than
  one that simply updates. Announced to assistive tech only once the affordance
  actually appears (Spec 007).
- **Empty-state honesty.** "No results" renders only for a *settled* empty
  response — never while a request is in flight, and never for a query below
  `min_length`.

### Interaction with existing behaviour

- **Spec 010 windowing** — scroll-triggered page fetches are appends, exempt
  from debounce and from supersession by id (they extend rather than replace).
- **ADR-012 invalid facets** — an invalid token contributes no clause and does
  not itself trigger a dispatch; the rest of the query dispatches per policy.
- **Open-with-no-input** — the initial listing dispatch is immediate under every
  policy, including `:enter`. Opening a picker and seeing nothing until you press
  Enter is indefensible.
- **`Flicker.palette`** — defaults to `:debounce` with the same 150ms; a ⌘K
  palette lives or dies on responsiveness.

## Non-goals

- **No client-side result caching or prefetching.** Tempting, and a bigger
  design (invalidation, memory, actor-scoped correctness — a cached result the
  actor may no longer read is a security bug, not a stale render). Separate spec
  if wanted.
- **No provider-declared policy.** A provider could plausibly advertise "I'm
  cheap, use `:immediate`", but a provider doesn't know the host's rate limits or
  data volume. The host chooses.
- **No per-facet policy.** Facet commits are always immediate; there is nothing
  left to configure.
- **No debounce on `fetch/2`** (label resolution for existing values) — that runs
  once on mount and isn't user-driven.

## Design

Because debounce and supersession are already handled below the component, what
remains is a small set of **decisions**, not a state machine. One pure module,
`Flicker.Dispatch`:

```elixir
# Should this input event dispatch at all?
@spec dispatch?(policy :: atom(), trigger :: :input | :enter | :facet_commit | :initial, text :: String.t(), min_length :: integer()) :: boolean()

# The value for phx-debounce, given the policy (nil omits the attribute).
@spec debounce_attr(policy :: atom(), debounce_ms :: integer()) :: integer() | nil

# Is there text typed that hasn't been dispatched? (drives the :enter hint)
@spec pending?(policy :: atom(), text :: String.t(), dispatched_text :: String.t()) :: boolean()

# Should "no results" render, or is this an in-flight / below-min-length state?
@spec empty_state(loading? :: boolean(), text :: String.t(), min_length :: integer(), results :: list()) ::
        :none | :no_results | :below_min_length | :listing
```

Every one is a pure function of its arguments, unit-testable with no LiveView, no
provider, and no browser — the same shape as `Flicker.CursorContext` and for the
same reason. The components keep owning the socket and the timers.

`loading_delay` is one timer with one job: set `loading?` only if the request is
still in flight when it fires. `Process.send_after/3` in the component,
cancelled when the response lands first.

### Theme parts (ADR-002)

`:results_stale` (the dimmed previous set), `:loading_indicator`,
`:dispatch_hint` (the "press Enter to search" affordance).

### Messages (ADR-009)

`press_enter_to_search/0`, `searching/0`, `results_updated/1` (the count, for the
live region).

## Acceptance criteria

- [ ] `:debounce` (the default) is byte-identical to current behaviour — the
      existing suite passes unchanged, and the rendered input still carries
      `phx-debounce="150"`.
- [ ] `:immediate` omits `phx-debounce` from the rendered input entirely.
- [ ] `:enter` omits `phx-debounce` and renders no dispatch on keyup.
- [ ] `:enter` dispatches nothing on typing, once on `Enter`, and renders the
      hint affordance plus its `aria-describedby` while text is pending.
- [ ] A facet commit dispatches immediately under all three policies.
- [ ] Pill removal dispatches immediately under all three policies.
- [ ] The initial open-with-no-input listing dispatches under all three policies.
- [ ] Supersession still holds: `select_stale_results_test.exs` passes unchanged,
      and its guarantee is documented rather than re-implemented.
- [ ] Previous results stay rendered (marked stale) while the next request is in
      flight; the result list never transitions through empty.
- [ ] No loading affordance appears for a request that resolves inside
      `loading_delay`; one appears for a slower request, and only then is it
      announced.
- [ ] "No results" never renders while a request is in flight, nor below
      `min_length`.
- [ ] `min_length: 2` dispatches nothing for one character and clears results to
      the listing state rather than to "no results".
- [ ] Spec 010's scroll-append fetches are neither debounced nor superseded.
- [ ] `Flicker.Dispatch` is exercised entirely by unit tests: every policy, every
      interleaving of input/timer/response, no LiveView involved.

## Open questions

None blocking.

- **Adaptive debounce.** Measuring observed provider latency and tuning the
  window would be genuinely nice and genuinely surprising; a fixed number is
  easier to reason about. Not now.
- **Cancellation.** Dropping a stale response is not the same as cancelling the
  work. `Ash` has no general cancellation story, and a `Task.shutdown` on a
  superseded query would need the provider contract to opt in. Worth a look if
  expensive providers show up.
