defmodule Flicker.Providers.RoutesTest do
  @moduledoc """
  Spec 011: destinations derived from a host's own router.

  The sharp edge under test is the authorisation caveat — this provider is
  structurally *not* policy-scoped, so the defaults must be conservative and
  `:visible?` must actually gate.
  """

  use ExUnit.Case, async: true

  alias Flicker.{Provider, Query}
  alias Flicker.Providers.Routes

  doctest Flicker.Providers.Routes

  @router Flicker.Test.Router
  @opts [router: @router]

  defp labels(opts), do: opts |> Routes.destinations() |> Enum.map(& &1.label)
  defp paths(opts \\ @opts), do: opts |> Routes.destinations() |> Enum.map(& &1.value)

  describe "what it offers" do
    test "derives a destination per navigable route" do
      refute Routes.destinations(@opts) == []
    end

    test "every result carries meta.href for Spec 008 navigate-on-select" do
      for result <- Routes.destinations(@opts) do
        assert result.meta.href == result.value
        assert String.starts_with?(result.meta.href, "/")
      end
    end

    test "results are grouped as Pages by default" do
      assert Enum.all?(Routes.destinations(@opts), &(&1.group == "Pages"))
    end

    test "the group can be overridden, or opted out of" do
      assert Enum.all?(Routes.destinations(@opts ++ [group: "Screens"]), &(&1.group == "Screens"))
      assert Enum.all?(Routes.destinations(@opts ++ [group: nil]), &(&1.group == nil))
    end

    test "paths are unique — one destination per path, not one per pipeline" do
      assert paths() == Enum.uniq(paths())
    end
  end

  describe "what it refuses to offer" do
    test "no parameterised paths — there is nothing to navigate to without an id" do
      refute Enum.any?(paths(), &String.contains?(&1, ":"))
      refute Enum.any?(paths(), &String.contains?(&1, "*"))
    end

    test "framework mounts are excluded by default" do
      for prefix <- ["/dev/", "/phoenix/", "/live_dashboard"] do
        refute Enum.any?(paths(), &String.starts_with?(&1, prefix)), "#{prefix} leaked in"
      end
    end
  end

  describe "only / except" do
    test ":only keeps just the matching prefixes" do
      [first | _] = paths()
      kept = paths(@opts ++ [only: [first]])

      assert Enum.all?(kept, &String.starts_with?(&1, first))
      refute kept == []
    end

    test ":except drops the matching prefixes" do
      [first | _] = paths()

      refute first in paths(@opts ++ [except: [first]])
    end

    test ":except replaces the framework defaults rather than adding to them" do
      # Documented behaviour: a host passing :except owns the whole list.
      assert is_list(paths(@opts ++ [except: []]))
    end
  end

  describe "visible? — the authorisation hook" do
    test "gates destinations for the current actor" do
      hidden = Routes.destinations(@opts ++ [visible?: fn _route, _actor -> false end])

      assert hidden == []
    end

    test "receives the route and the actor" do
      test_pid = self()

      Routes.destinations(
        @opts ++
          [
            actor: %{id: 7},
            visible?: fn route, actor ->
              send(test_pid, {:asked, route.path, actor})
              true
            end
          ]
      )

      assert_received {:asked, _path, %{id: 7}}
    end

    test "with no hook everything given is offered — this provider is not policy-scoped" do
      # Stated plainly because it is the feature's sharp edge: absence of a
      # hook means absence of gating, not a safe default.
      assert length(Routes.destinations(@opts)) ==
               length(Routes.destinations(@opts ++ [visible?: fn _r, _a -> true end]))
    end
  end

  describe "labels" do
    test "are humanised from the path" do
      assert Routes.derive_label("/") == "Home"
      assert Routes.derive_label("/artists") == "Artists"
      assert Routes.derive_label("/user-settings/billing") == "User settings · Billing"
      assert Routes.derive_label("/user_settings") == "User settings"
    end

    test "can be overridden wholesale" do
      assert Enum.all?(labels(@opts ++ [label: fn _route -> "X" end]), &(&1 == "X"))
    end
  end

  describe "extra destinations" do
    test "are appended, for parameterised favourites the router can't supply" do
      results = Routes.destinations(@opts ++ [extra: [%{label: "My profile", href: "/users/42"}]])

      assert Enum.any?(results, &(&1.label == "My profile" and &1.meta.href == "/users/42"))
    end

    test "may carry their own group" do
      results = Routes.destinations(@opts ++ [extra: [%{label: "X", href: "/x", group: "Mine"}]])

      assert Enum.any?(results, &(&1.group == "Mine"))
    end
  end

  describe "as a provider" do
    test "search/2 filters by label, case-insensitively" do
      {:ok, all} = Provider.run_search({Routes, @opts}, %Query{text: ""})
      [sample | _] = all
      needle = sample.label |> String.slice(0, 3) |> String.upcase()

      {:ok, matched} = Provider.run_search({Routes, @opts}, %Query{text: needle})

      refute matched == []
      assert Enum.all?(matched, &String.contains?(String.downcase(&1.label), String.downcase(needle)))
    end

    test "a blank query lists everything, so the palette opens populated" do
      {:ok, results} = Provider.run_search({Routes, @opts}, %Query{text: ""})

      assert length(results) == length(Routes.destinations(@opts))
    end

    test "facets are ignored — a route has no attributes to facet on" do
      {:ok, with_facets} =
        Provider.run_search({Routes, @opts}, %Query{text: "", facets: [{:status, :eq, :active}]})

      {:ok, without} = Provider.run_search({Routes, @opts}, %Query{text: ""})

      assert length(with_facets) == length(without)
    end

    test ":limit caps the result list" do
      {:ok, results} = Provider.run_search({Routes, Keyword.put(@opts, :limit, 1)}, %Query{text: ""})

      assert length(results) == 1
    end

    test "fetch/2 resolves hrefs back to labelled results" do
      [%{value: path} | _] = Routes.destinations(@opts)

      {:ok, [result]} = Provider.run_fetch({Routes, @opts}, [path])

      assert result.value == path
    end

    test "fetch/2 omits unresolvable values rather than erroring (ADR-003)" do
      assert {:ok, []} = Provider.run_fetch({Routes, @opts}, ["/nope-does-not-exist"])
    end
  end
end
