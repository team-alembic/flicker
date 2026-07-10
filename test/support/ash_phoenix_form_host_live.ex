if Code.ensure_loaded?(AshPhoenix.Form) do
  defmodule Flicker.Test.AshPhoenixFormHostLive do
    @moduledoc """
    Exercises `Flicker.AshPhoenixForm.attach/2` with a `to_form/2` name
    (`"artist"`) that deliberately differs from the socket assign key it
    lives under (`:form`) — the exact shape that surfaces the root-name
    matching bug (a resource-derived form name doesn't have to equal the
    assign key it's stored at).

    Test-support only; only compiled when `ash_phoenix` is present.
    """

    use Phoenix.LiveView

    alias Flicker.Test.{PolicyArtist, PolicyDomain}

    @impl true
    def mount(_params, _session, socket) do
      PolicyDomain.seed!()

      form =
        PolicyArtist
        |> AshPhoenix.Form.for_create(:create, as: "artist")
        |> to_form()

      socket =
        socket
        |> assign(:form, form)
        |> Flicker.AshPhoenixForm.attach(form: :form)

      {:ok, socket}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <.form for={@form} id="artist-form">
        <Flicker.select
          id="label-picker"
          field={@form[:label]}
          resource={PolicyArtist}
          actor={%{label: nil}}
          search={[:name]}
          option_label={:name}
        />
      </.form>
      <pre id="form-params">{inspect(@form.source.params)}</pre>
      """
    end
  end
end
