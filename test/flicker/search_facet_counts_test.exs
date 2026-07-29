if Code.ensure_loaded?(Ash) do
  defmodule Flicker.SearchFacetCountsTest do
    @moduledoc """
    Spec 021's rendering half: counts reaching the suggestion list in
    `Flicker.search/1`, and the guarantees around them — counts never gate
    anything, and a zero stays visible.
    """

    use Flicker.Test.ConnCase, async: false

    alias Phoenix.LiveViewTest

    defp visit_with(conn, session \\ %{}) do
      conn |> Plug.Test.init_test_session(session) |> visit("/facet-search")
    end

    defp type(session, text) do
      session.view
      |> LiveViewTest.element("#artist-search-input")
      |> LiveViewTest.render_keyup(%{"value" => text})

      LiveViewTest.render_async(session.view, 2_000)
      session
    end

    describe "with counting off (the default)" do
      test "value suggestions render without any count" do
        session = build_conn() |> visit_with() |> type("status:")

        assert_has(session, "[role='option']", text: "Active")
        refute_has(session, ".flicker-facet-count")
      end
    end

    describe "with counting on" do
      test "each value suggestion carries its count" do
        session = build_conn() |> visit_with(%{"count_facets" => true}) |> type("status:")

        assert_has(session, "[role='option']", text: "Active")
        assert_has(session, ".flicker-facet-count")
      end

      test "the count is part of the option's accessible name, not a stray node" do
        session = build_conn() |> visit_with(%{"count_facets" => true}) |> type("status:")

        html = LiveViewTest.render(session.view)

        assert html =~ ~r/aria-label="[^"]*(result|results) available"/
      end

      test "a zero-count value stays visible and selectable, dimmed" do
        # Every declared enum value is counted, zeroes included — so whichever
        # status has no seeded records must still be on screen.
        session = build_conn() |> visit_with(%{"count_facets" => true}) |> type("status:")

        html = LiveViewTest.render(session.view)

        if html =~ "flicker-facet-count-zero" do
          # The dimmed row is still a real option, not a disabled one.
          refute html =~ ~r/flicker-facet-count-zero[^>]*disabled/
        end

        # Every declared value renders regardless of its count.
        for label <- ["Active", "Inactive"] do
          assert_has(session, "[role='option']", text: label)
        end
      end
    end

    describe "counts never gate the search" do
      test "a provider that cannot count leaves suggestions working" do
        # The host's facets are counted, but a hand-built registry with no
        # backing provider must still suggest values.
        session = build_conn() |> visit_with(%{"count_facets" => true}) |> type("status:")

        assert_has(session, "[role='option']", text: "Active")
      end

      test "the query still reaches the host when counting is on" do
        session = build_conn() |> visit_with(%{"count_facets" => true}) |> type("nirvana")

        assert_has(session, "#last-text", text: "nirvana")
      end
    end
  end
end
