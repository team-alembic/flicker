if Code.ensure_loaded?(Ash) do
  defmodule Flicker.SelectFacetTriggerTest do
    @moduledoc """
    Spec 024 inside `Flicker.select/1`, where the trigger earns its keep most
    clearly: this component's primary job is finding a *record*, so a bare word
    must search records rather than volunteer facet keys.
    """

    use Flicker.Test.ConnCase, async: false

    alias Phoenix.LiveViewTest

    defp visit_select(session \\ %{}) do
      build_conn()
      |> Plug.Test.init_test_session(Map.merge(%{"actor" => %{label: nil}}, session))
      |> visit("/facet-select")
    end

    defp type(session, text) do
      session.view
      |> LiveViewTest.element("#artist-picker-input")
      |> LiveViewTest.render_keyup(%{"value" => text})

      LiveViewTest.render_async(session.view, 2_000)
      session
    end

    defp listbox(session) do
      case Regex.run(~r{<ul [^>]*role="listbox".*?</ul>}s, LiveViewTest.render(session.view)) do
        [html] -> html
        nil -> ""
      end
    end

    describe "the trigger keeps record search out of the facets' way" do
      test "a word that happens to prefix a facet key searches records instead" do
        # Without a trigger, typing "st" offers `status:` — which is exactly the
        # complaint: the user is looking for a band, not a filter.
        session = visit_select(%{"facet_trigger" => "@"}) |> type("st")

        refute listbox(session) =~ "status:"
      end

      test "and the same word does offer the key with no trigger configured" do
        session = visit_select() |> type("st")

        assert listbox(session) =~ "status:"
      end

      test "the trigger opens the facet menu" do
        session = visit_select(%{"facet_trigger" => "@"}) |> type("@st")

        assert listbox(session) =~ "status:"
      end

      test "a facet typed out in full still filters the record search" do
        session = visit_select(%{"facet_trigger" => "@"}) |> type("status:active ")

        assert_has(session, "[role='listitem']", text: "Status")
      end

      test "the hint tells the user the trigger exists" do
        session = visit_select(%{"facet_trigger" => "@"})

        assert_has(session, "#artist-picker-input-trigger-hint", text: "Type @ to filter")

        assert_has(
          session,
          "#artist-picker-input[aria-describedby~='artist-picker-input-trigger-hint']"
        )
      end

      test "no hint without a trigger" do
        refute_has(visit_select(), "#artist-picker-input-trigger-hint")
      end
    end
  end
end
