if Code.ensure_loaded?(Ash) do
  defmodule Flicker.SearchRecentValuesTest do
    @moduledoc """
    Spec 022 in `Flicker.search/1`: the `Recent` group, when it appears, and the
    guarantee that a remembered value is only ever a hint — never a way to
    surface something the facet or the actor no longer allows.
    """

    use Flicker.Test.ConnCase, async: false

    alias Flicker.RecentValues.Ets
    alias Phoenix.LiveViewTest

    setup do
      Ets.clear()
      :ok
    end

    defp visit_with(session_data) do
      build_conn() |> Plug.Test.init_test_session(session_data) |> visit("/facet-search")
    end

    defp type(session, text) do
      session.view
      |> LiveViewTest.element("#artist-search-input")
      |> LiveViewTest.render_keyup(%{"value" => text})

      LiveViewTest.render_async(session.view, 2_000)
      session
    end

    defp option_labels(session) do
      session.view
      |> LiveViewTest.render()
      |> then(&Regex.scan(~r/role="option"[^>]*>.*?<span>([^<]+)<\/span>/s, &1))
      |> Enum.map(fn [_, label] -> label end)
    end

    describe "with no recent_values configured" do
      test "nothing changes about the suggestion list" do
        session = visit_with(%{}) |> type("status:")

        assert_has(session, "[role='option']", text: "Active")
        assert option_labels(session) == ["Active", "Inactive"]
      end
    end

    describe "with a store configured" do
      test "a used value is recorded and then offered first" do
        session = visit_with(%{"recent_values" => true}) |> type("status:")

        # Commit `inactive` — the second value in declaration order.
        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("select_suggestion", %{"insert" => "status:inactive "})

        LiveViewTest.render_async(session.view, 2_000)

        # Reopening value position now surfaces it at the top.
        type(session, "status:")

        assert [first | _] = option_labels(session)
        assert first == "Inactive"
      end

      test "a recent value is not duplicated in the ordinary list" do
        session = visit_with(%{"recent_values" => true}) |> type("status:")

        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("select_suggestion", %{"insert" => "status:active "})

        LiveViewTest.render_async(session.view, 2_000)

        type(session, "status:")

        labels = option_labels(session)

        assert Enum.count(labels, &(&1 == "Active")) == 1
      end

      test "the group is suppressed once a prefix is typed" do
        # Once you're typing you've said what you want; a recency row above the
        # match would just be a duplicate.
        session = visit_with(%{"recent_values" => true}) |> type("status:")

        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("select_suggestion", %{"insert" => "status:inactive "})

        LiveViewTest.render_async(session.view, 2_000)

        type(session, "status:inact")

        assert option_labels(session) == ["Inactive"]
      end
    end

    describe "a remembered value is a hint, not a bypass" do
      test "a value no longer in the facet's closed set is silently dropped" do
        # Recorded directly into the store, as if the enum had since changed.
        Ets.record(:status, :retired_value, [])

        session = visit_with(%{"recent_values" => true}) |> type("status:")

        labels = option_labels(session)

        refute "retired_value" in labels
        assert labels == ["Active", "Inactive"]
      end

      test "nothing is announced about a dropped value" do
        Ets.record(:status, :retired_value, [])

        session = visit_with(%{"recent_values" => true}) |> type("status:")

        html = LiveViewTest.render(session.view)

        refute html =~ "retired_value"
      end

      test "history is per actor, so one actor's values never leak to another" do
        Ets.record(:status, :inactive, actor: %{label: "major"})

        # The host mounts with a different actor, so that history isn't theirs.
        session = visit_with(%{"recent_values" => true, "actor" => %{label: "indie"}}) |> type("status:")

        assert option_labels(session) == ["Active", "Inactive"]
      end
    end

    describe "recording happens on commit only" do
      test "typing a value without committing records nothing" do
        visit_with(%{"recent_values" => true}) |> type("status:inactive")

        assert Ets.load(:status, []) == []
      end

      test "an invalid value is never recorded" do
        visit_with(%{"recent_values" => true}) |> type("status:activ ")

        assert Ets.load(:status, []) == []
      end
    end
  end
end
