if Code.ensure_loaded?(Ash) do
  defmodule Flicker.PaletteFacetsTest do
    @moduledoc """
    Closes Spec 008's open question: `Flicker.palette/1` accepts and
    forwards `facets` (Spec 003), but it "hasn't been exercised end-to-end
    in the playground". Drives facet-key/value suggestion and a
    facet-narrowed selection through `Flicker.palette/1` itself — not just
    `Flicker.select/1`, which `Flicker.SelectFacetsTest` already covers, or
    `Dev.Providers.MusicSearch` in isolation (`Flicker.MusicSearchFacetsTest`)
    — proving the palette's thin wrapper really does forward `facets`
    unchanged to its nested `Flicker.Components.Select` core.
    """

    use Flicker.Test.ConnCase, async: true

    import Flicker.Test.Helpers

    @moduletag :ash

    defp visit_palette(conn), do: visit(conn, "/palette-facets")

    test "typing a facet key shows key suggestions instead of record results", %{conn: conn} do
      session = conn |> visit_palette() |> type_search("cmdk-select-input", "stat")

      assert_has(session, "[role='option']", text: "status:")
      refute_has(session, "[role='option']", text: "Riley Rivers")
    end

    test "picking a facet-key suggestion edits the text instead of selecting a record", %{conn: conn} do
      session = conn |> visit_palette() |> type_search("cmdk-select-input", "stat")

      session = click_button(session, "status:")

      assert_has(session, "#cmdk-select-input[value='status:']")
      refute_has(session, "#palette-selection")
    end

    test "picking a facet-value suggestion completes the token instead of selecting a record", %{conn: conn} do
      session = conn |> visit_palette() |> type_search("cmdk-select-input", "status:")

      session = click_button(session, "Active")

      # Spec 015: the completed facet lifts out of the input into a pill,
      # leaving the buffer for free text — the same commit boundary
      # `Flicker.search` uses. The token is no longer raw text in the field.
      assert_has(session, "[role='listitem']", text: "Active")
      assert_has(session, "#cmdk-select-input[value='']")
      refute_has(session, "#palette-selection")
    end

    # Regression (mirrors `Flicker.SelectFacetsTest`): "Jordan Blake" and
    # "Joey Turner" both match the free-text prefix "jo", but only "Joey
    # Turner" is `status: :active` — proves the completed facet token
    # narrows *which records* the palette's nested search considers, not
    # just the free text, exactly as `Flicker.select/1` does.
    test "a completed facet token narrows the record search through Flicker.palette/1", %{conn: conn} do
      session = conn |> visit_palette() |> type_search("cmdk-select-input", "status:active jo")

      assert_has(session, "[role='option']", text: "Joey Turner")
      refute_has(session, "[role='option']", text: "Jordan Blake")
    end

    test "free text after a completed facet still selects a record through the palette", %{conn: conn} do
      session = conn |> visit_palette() |> type_search("cmdk-select-input", "status:active Riley")

      session = click_button(session, "Riley Rivers")

      assert_has(session, "#palette-selection", text: "Riley Rivers")
    end
  end
end
