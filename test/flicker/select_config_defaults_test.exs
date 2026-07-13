defmodule Flicker.SelectConfigDefaultsTest do
  @moduledoc """
  `Flicker.select/1` falls back to `config :flicker, default_limit:` and
  `default_debounce:` when the host doesn't pass those attrs (Spec 001).
  """

  # Mutates global `:flicker` Application env — not safe to run
  # concurrently with other tests that read it.
  use Flicker.Test.ConnCase, async: false

  setup do
    on_exit(fn ->
      Application.delete_env(:flicker, :default_limit)
      Application.delete_env(:flicker, :default_debounce)
    end)
  end

  test "renders the configured default_debounce on the search input", %{conn: conn} do
    Application.put_env(:flicker, :default_debounce, 999)

    session = conn |> Plug.Test.init_test_session(%{"mode" => "controlled"}) |> visit("/")

    assert_has(session, "#picker-input[phx-debounce='999']")
  end

  test "renders the phoenix_live_view default (150) with no config set", %{conn: conn} do
    session = conn |> Plug.Test.init_test_session(%{"mode" => "controlled"}) |> visit("/")

    assert_has(session, "#picker-input[phx-debounce='150']")
  end

  test "the configured default_limit caps how many results are shown before the 'keep typing' hint", %{
    conn: conn
  } do
    Application.put_env(:flicker, :default_limit, 2)

    session = conn |> Plug.Test.init_test_session(%{"mode" => "controlled"}) |> visit("/")

    # Opening the picker (rather than typing) runs the blank-query search —
    # `type_search("")` would be a no-op since the query is already "".
    session.view |> Phoenix.LiveViewTest.element("#picker-input") |> Phoenix.LiveViewTest.render_focus()
    Phoenix.LiveViewTest.render_async(session.view, 2_000)

    assert_has(session, "li", text: "Keep typing to narrow results")
  end
end
