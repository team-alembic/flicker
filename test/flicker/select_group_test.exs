defmodule Flicker.SelectGroupTest do
  @moduledoc """
  Covers `Flicker.Result`'s optional `:group` field (Spec 008): the core
  listbox renders a contiguous group-header row before the first result of
  each new group, and a groupless result list (every `:group` is the
  default `nil`) renders exactly as it always has. This is generic core
  behaviour — `Flicker.select/1` renders it the same as `Flicker.palette/1`
  does, since neither branches on which one it is.
  """

  use Flicker.Test.ConnCase, async: true

  import Flicker.Test.Helpers
  import Phoenix.LiveViewTest, only: [render: 1]

  @grouped [
    %Flicker.Result{value: "1", label: "Casey Cassidy", group: "Artists"},
    %Flicker.Result{value: "2", label: "Casey's Album", group: "Albums"},
    %Flicker.Result{value: "3", label: "Casey's Other Album", group: "Albums"}
  ]

  @groupless [
    %Flicker.Result{value: "1", label: "Casey Cassidy"},
    %Flicker.Result{value: "2", label: "Casey's Album"},
    %Flicker.Result{value: "3", label: "Casey's Other Album"}
  ]

  defp visit_with_results(conn, results) do
    conn =
      Plug.Test.init_test_session(conn, %{
        "mode" => "controlled",
        "provider" => {Flicker.Providers.Static, results: results}
      })

    visit(conn, "/")
  end

  test "a contiguous group header renders before the first result of each new group", %{conn: conn} do
    session = conn |> visit_with_results(@grouped) |> type_search("picker-input", "cas")

    html = render(session.view)

    artists_index = :binary.match(html, "Artists") |> elem(0)
    casey_index = :binary.match(html, "Casey Cassidy") |> elem(0)
    albums_index = :binary.match(html, "Albums") |> elem(0)

    assert artists_index < casey_index
    assert casey_index < albums_index
    # Contiguous: exactly one "Albums" header, not one per album result.
    assert html |> String.split("Albums") |> length() == 2
  end

  test "a groupless result list renders with no group header at all", %{conn: conn} do
    session = conn |> visit_with_results(@groupless) |> type_search("picker-input", "cas")

    refute_has(session, ".flicker-group-header")
    assert_has(session, "[role='option']", text: "Casey Cassidy")
    assert_has(session, "[role='option']", text: "Casey's Album")
  end
end
