if Code.ensure_loaded?(Ash) do
  defmodule Flicker.FacetValueColorsTest do
    @moduledoc """
    Spec 017: a facet may declare a colour per value, shown as a leading dot on
    that value's pill. Host-supplied CSS colours — Flicker assumes no palette of
    its own, so an unconfigured value must render uncoloured rather than picking
    something.
    """

    use Flicker.Test.ConnCase, async: false

    alias Phoenix.LiveViewTest

    defp visit_search do
      build_conn() |> Plug.Test.init_test_session(%{}) |> visit("/facet-search")
    end

    defp commit(session, text) do
      session.view
      |> LiveViewTest.element("#artist-search-input")
      |> LiveViewTest.render_keyup(%{"value" => text})

      LiveViewTest.render_async(session.view, 2_000)
      session
    end

    describe "a configured value" do
      test "renders its host-supplied colour as an inline style" do
        # The host fixture configures `active: "#16a34a"` and nothing else.
        session = visit_search() |> commit("status:active ")

        assert LiveViewTest.render(session.view) =~ "background-color:#16a34a"
      end

      test "the indicator is decorative, not announced" do
        session = visit_search() |> commit("status:active ")
        html = LiveViewTest.render(session.view)

        dot = Regex.run(~r/<span[^>]*background-color:#16a34a[^>]*>/, html) |> List.first()

        assert dot =~ ~s(aria-hidden="true")
      end
    end

    describe "an unconfigured value" do
      test "renders uncoloured, with no crash and no invented colour" do
        session = visit_search() |> commit("status:inactive ")
        html = LiveViewTest.render(session.view)

        assert html =~ "Inactive"
        refute html =~ "background-color:#16a34a"
        refute html =~ "background-color:;"
      end

      test "a facet with no value_colours at all renders its pill fine" do
        session = visit_search() |> commit("verified?:true ")

        assert_has(session, "[role='listitem']", text: "Verified?")
        refute LiveViewTest.render(session.view) =~ "background-color:"
      end
    end

    describe "no built-in palette is assumed" do
      test "the colour comes only from the facet's own configuration" do
        facet = Flicker.Facet.new(key: :status, type: :enum, values: [:a, :b])

        # Nothing configured means nothing to render — Flicker never guesses.
        assert facet.value_colors == nil
      end

      test "any CSS colour string is accepted verbatim" do
        for colour <- ["red", "#abc", "rgb(1 2 3)", "var(--brand)"] do
          facet = Flicker.Facet.new(key: :s, type: :enum, values: [:x], value_colors: %{x: colour})

          assert facet.value_colors[:x] == colour
        end
      end
    end
  end
end
