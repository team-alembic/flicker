if Code.ensure_loaded?(AshPhoenix.Form) do
  defmodule Flicker.AshPhoenixForm do
    @moduledoc """
    An optional `AshPhoenix.Form` adapter for form-field mode (ADR-005).

    This module only compiles when `ash_phoenix` is present — `ash_phoenix`
    is not a hard dependency of Flicker (ADR-006). Plain Phoenix forms and
    controlled mode don't need it at all.

    A `Flicker.select/1` in form-field mode owns its own hidden input, but
    applying a selection also needs to land in the host's
    `%AshPhoenix.Form{}` so the rest of the form (validation, other fields'
    `_unused_` markers) doesn't get reset out from under it. `attach/2`
    installs one `handle_info` hook per host form that does exactly that —
    merging the selected value into the form's existing raw params rather
    than replacing them (the hard-won part of ADR-005; ported from the
    origin implementation per the extraction notes).

    ## Usage

        def mount(_params, _session, socket) do
          {:ok, socket |> assign(form: to_form(...)) |> Flicker.AshPhoenixForm.attach(form: :form)}
        end

    Pass `on_select: fn socket, form -> socket end` to run further logic
    (e.g. loading a dependent field's options) after the form revalidates.
    """

    alias Phoenix.LiveView

    @doc """
    Attaches a `:handle_info` hook to `socket` that applies Flicker
    selections targeting the `AshPhoenix.Form` assigned at `opts[:form]`.

    `opts`:

      * `:form` — required. The socket assign key holding the
        `%AshPhoenix.Form{}` (as passed to `to_form/2`).
      * `:on_select` — optional `fun(socket, form) :: socket`, run after the
        form revalidates.
    """
    @spec attach(LiveView.Socket.t(), keyword()) :: LiveView.Socket.t()
    def attach(socket, opts) do
      form_key = Keyword.fetch!(opts, :form)
      on_select = Keyword.get(opts, :on_select)

      LiveView.attach_hook(socket, {__MODULE__, form_key}, :handle_info, fn
        {Flicker.Components.Select, :selected, field_name, value}, socket ->
          handle_selection(socket, form_key, field_name, value, on_select)

        _message, socket ->
          {:cont, socket}
      end)
    end

    defp handle_selection(socket, form_key, field_name, value, on_select) do
      form = Map.fetch!(socket.assigns, form_key)

      case parse_field_name(field_name) do
        {root, key} ->
          # `field_name` is the field's actual param name (e.g.
          # "artist[client_id]"), which is `form.name`-derived, not the
          # socket assign key `form_key` lives under — those two only
          # coincide by accident (e.g. `assign(:form, ...)` with no `as:`
          # override and a resource literally named "form").
          if root == form.name do
            params =
              (form.source.params || %{})
              |> Map.put(key, value)
              |> Map.delete("_unused_#{key}")

            new_form = AshPhoenix.Form.validate(form, params)
            socket = Phoenix.Component.assign(socket, form_key, new_form)
            socket = if on_select, do: on_select.(socket, new_form), else: socket
            {:halt, socket}
          else
            {:cont, socket}
          end

        :error ->
          {:cont, socket}
      end
    end

    # e.g. "form[client_id]" -> {"form", "client_id"}
    defp parse_field_name(field_name) do
      case Regex.run(~r/^([^\[]+)\[([^\]]+)\]$/, field_name) do
        [_full, root, key] -> {root, key}
        nil -> :error
      end
    end
  end
end
