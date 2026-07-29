if Code.ensure_loaded?(Ash) do
  defmodule Flicker.SearchInvalidValueTest do
    @moduledoc """
    Spec 023 in `Flicker.search/1`: the `on_invalid` policy, the error
    rendering, and accepting a correction.

    `Flicker.CorrectionTest` covers the ranking and the fixes in isolation;
    this covers that they reach the screen, that the error is conspicuous
    rather than a tooltip, and that `:require` withholds the query without
    making itself unusable mid-type.
    """

    use Flicker.Test.ConnCase, async: false

    alias Phoenix.LiveViewTest

    defp visit_with(conn, session \\ %{}) do
      conn |> Plug.Test.init_test_session(session) |> visit("/facet-search")
    end

    defp type(session, text, cursor \\ nil) do
      params = if cursor, do: %{"value" => text, "cursor" => to_string(cursor)}, else: %{"value" => text}

      session.view
      |> LiveViewTest.element("#artist-search-input")
      |> LiveViewTest.render_keyup(params)

      LiveViewTest.render_async(session.view, 2_000)
      session
    end

    describe "the error is conspicuous" do
      test "an invalid value renders its reason as visible text", %{conn: conn} do
        session = conn |> visit_with() |> type("status:activ ")

        assert_has(session, "#artist-search-input-facet-error")
        assert_has(session, "#artist-search-input-facet-error", text: "must be one of")
      end

      test "the token the user typed is shown back to them", %{conn: conn} do
        session = conn |> visit_with() |> type("status:activ ")

        assert_has(session, "#artist-search-input-facet-error", text: "status:activ")
      end

      test "the input is marked invalid and points at the message", %{conn: conn} do
        session = conn |> visit_with() |> type("status:activ ")

        assert_has(session, "#artist-search-input[aria-invalid='true']")
        assert_has(session, "#artist-search-input[aria-describedby*='artist-search-input-facet-error']")
      end

      test "a valid query renders no error and no aria-invalid", %{conn: conn} do
        session = conn |> visit_with() |> type("status:active ")

        refute_has(session, "#artist-search-input-facet-error")
        refute_has(session, "#artist-search-input[aria-invalid]")
      end
    end

    describe "corrections" do
      test "a near-miss offers the intended value", %{conn: conn} do
        session = conn |> visit_with() |> type("status:activ ")

        assert_has(session, "#artist-search-input-facet-error", text: "Did you mean")
      end

      test "accepting the correction fixes the token and clears the error", %{conn: conn} do
        session = conn |> visit_with() |> type("status:activ ")

        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("accept_correction", %{"insert" => "status:active "})

        LiveViewTest.render_async(session.view, 2_000)

        refute_has(session, "#artist-search-input-facet-error")
        assert_has(session, "[role='listitem']", text: "Active")
      end

      test "an implausible value offers no suggestion, only the shape", %{conn: conn} do
        session = conn |> visit_with() |> type("status:banana ")

        assert_has(session, "#artist-search-input-facet-error", text: "must be one of")
        refute_has(session, "#artist-search-input-facet-error", text: "Did you mean")
      end
    end

    describe "on_invalid: :drop (default)" do
      test "the rest of the query still reaches the host", %{conn: conn} do
        session = conn |> visit_with() |> type("status:activ nirvana ")

        # The broken facet contributes nothing, but the free text still runs.
        assert_has(session, "#last-text", text: "nirvana")
      end

      test "no blocked notice is shown", %{conn: conn} do
        session = conn |> visit_with() |> type("status:activ ")

        refute_has(session, "#artist-search-input-facet-error", text: "Filter not applied")
      end
    end

    describe "on_invalid: :require" do
      test "withholds the query entirely while a value is broken", %{conn: conn} do
        session = conn |> visit_with(%{"on_invalid" => :require}) |> type("status:activ nirvana ")

        refute_has(session, "#last-text")
      end

      test "says so, visibly", %{conn: conn} do
        session = conn |> visit_with(%{"on_invalid" => :require}) |> type("status:activ ")

        assert_has(session, "#artist-search-input-facet-error", text: "Filter not applied")
      end

      test "does not withhold on the token the caret is still inside", %{conn: conn} do
        # Half-typed input is expected to be invalid. Blocking dispatch on
        # every keystroke of `status:a`, `status:ac` would make the policy
        # unusable, so the in-progress token is exempt from the gate.
        text = "nirvana status:activ"
        session = conn |> visit_with(%{"on_invalid" => :require}) |> type(text, String.length(text))

        assert_has(session, "#last-text", text: "nirvana")
      end

      test "withholds once the caret leaves that token", %{conn: conn} do
        # Caret at the end, which is inside `nirvana` — so the broken
        # `status:activ` earlier in the buffer is no longer in progress and
        # does block. (Caret 0 would *not* qualify: offset 0 is inside the
        # first token, at its start.)
        text = "status:activ nirvana"
        session = conn |> visit_with(%{"on_invalid" => :require}) |> type(text, String.length(text))

        refute_has(session, "#last-text")
      end

      test "dispatch resumes once the value is corrected", %{conn: conn} do
        session = conn |> visit_with(%{"on_invalid" => :require}) |> type("status:activ nirvana ")

        refute_has(session, "#last-text")

        session.view
        |> LiveViewTest.element("#artist-search")
        |> LiveViewTest.render_hook("accept_correction", %{"insert" => "status:active "})

        LiveViewTest.render_async(session.view, 2_000)

        assert_has(session, "#last-filter")
      end
    end

    describe "the invalid value never reaches the query" do
      test "under either policy", %{conn: conn} do
        for policy <- [:drop, :require] do
          session = conn |> visit_with(%{"on_invalid" => policy}) |> type("status:activ ")

          # `#last-filter` only renders once a query was emitted; under :drop it
          # is emitted without the status clause, under :require not at all.
          # Either way nothing mentions the rejected value.
          refute_has(session, "#last-filter", text: "activ")
        end
      end
    end
  end
end
