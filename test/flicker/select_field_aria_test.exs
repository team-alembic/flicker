defmodule Flicker.SelectFieldAriaTest do
  @moduledoc """
  Covers the attrs a host form field uses to own the combobox's accessible
  name and description (`aria_labelledby`, `aria_describedby`,
  `aria_invalid`), and the keyless "query" push the colocated hook sends for
  pasted, dropped, or autofilled text.

  The hook's `input` listener itself is client-side JS. ExUnit can only send
  the event it pushes and check the server runs a search for it.
  """

  use Flicker.Test.ConnCase, async: true

  import Phoenix.LiveViewTest

  defmodule FieldHostLive do
    @moduledoc false
    use Phoenix.LiveView

    @results [
      %Flicker.Result{value: "1", label: "Casey Cassidy", sublabel: "Bass"},
      %Flicker.Result{value: "2", label: "Alex Rivers", sublabel: "Drums"}
    ]

    @impl true
    def mount(_params, session, socket) do
      socket =
        socket
        |> Phoenix.Component.assign(:aria, Map.get(session, "aria", %{}))
        |> Phoenix.Component.assign(:dispatch, Map.get(session, "dispatch", :immediate))

      {:ok, socket}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <label id="host-label" for="picker-input">Language</label>
      <Flicker.select
        id="picker"
        source={{Flicker.Providers.Static, results: results()}}
        on_select={:picked}
        dispatch={@dispatch}
        aria_labelledby={@aria["labelledby"]}
        aria_describedby={@aria["describedby"]}
        aria_invalid={@aria["invalid"] || false}
      />
      """
    end

    defp results, do: @results
  end

  defp mount_host(conn, aria, dispatch \\ :immediate) do
    live_isolated(conn, FieldHostLive, session: %{"aria" => aria, "dispatch" => dispatch})
  end

  describe "aria_labelledby" do
    test "without it, Flicker's own sr-only label names the input and listbox", %{conn: conn} do
      {:ok, view, html} = mount_host(conn, %{})

      assert html =~ ~s(id="picker-input-label")
      refute has_element?(view, "#picker-input[aria-labelledby]")

      view |> element("#picker-input") |> render_focus()
      assert has_element?(view, "[role=listbox][aria-labelledby='picker-input-label']")
    end

    test "with it, the sr-only label is dropped and the host's id names input and listbox", %{conn: conn} do
      {:ok, view, html} = mount_host(conn, %{"labelledby" => "host-label"})

      refute html =~ ~s(id="picker-input-label")
      assert has_element?(view, "#picker-input[aria-labelledby='host-label']")

      view |> element("#picker-input") |> render_focus()
      assert has_element?(view, "[role=listbox][aria-labelledby='host-label']")
    end
  end

  describe "aria_describedby" do
    test "is absent by default", %{conn: conn} do
      {:ok, view, _html} = mount_host(conn, %{})
      refute has_element?(view, "#picker-input[aria-describedby]")
    end

    test "carries the host's ids", %{conn: conn} do
      {:ok, view, _html} = mount_host(conn, %{"describedby" => "field-help field-error"})
      assert has_element?(view, "#picker-input[aria-describedby='field-help field-error']")
    end

    test "follows Flicker's own hint ids", %{conn: conn} do
      {:ok, view, _html} = mount_host(conn, %{"describedby" => "field-help"}, :enter)

      view |> element("#picker-input") |> render_keyup(%{"value" => "cas"})

      assert has_element?(view, "#picker-input[aria-describedby='picker-input-dispatch-hint field-help']")
    end
  end

  describe "aria_invalid" do
    test "is not rendered when false", %{conn: conn} do
      {:ok, view, _html} = mount_host(conn, %{})
      refute has_element?(view, "#picker-input[aria-invalid]")
    end

    test "renders aria-invalid=true when true", %{conn: conn} do
      {:ok, view, _html} = mount_host(conn, %{"invalid" => true})
      assert has_element?(view, "#picker-input[aria-invalid='true']")
    end
  end

  describe "keyless input" do
    test "a hook-pushed query with no key runs a search", %{conn: conn} do
      {:ok, view, _html} = mount_host(conn, %{})

      view |> element("#picker") |> render_hook("query", %{"value" => "cas", "cursor" => "3"})
      html = render_async(view)

      assert html =~ "Casey Cassidy"
      refute html =~ "Alex Rivers"
    end
  end
end
