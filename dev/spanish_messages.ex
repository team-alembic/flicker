defmodule Dev.SpanishMessages do
  @moduledoc """
  A Spanish `Flicker.Messages` implementation for the playground's
  internationalisation demo — proving every user-facing string and
  screen-reader announcement routes through `Flicker.Messages` (ADR-009), so a
  host localises Flicker by supplying a module, no library change needed.

  Only the visible/announced strings the demo exercises are overridden; every
  other key delegates to `Flicker.Messages.English`, the pattern the
  `Flicker.Messages` moduledoc documents.
  """

  @behaviour Flicker.Messages

  @impl true
  def message(:search_placeholder, _bindings), do: "Buscar..."
  def message(:facet_search_placeholder, _bindings), do: "Filtrar... (prueba status:active)"
  def message(:no_results, _bindings), do: "Sin resultados"
  def message(:loading, _bindings), do: "Cargando..."
  def message(:error, _bindings), do: "Algo salió mal"
  def message(:clear_selection, _bindings), do: "Borrar"
  def message(:clear_all, _bindings), do: "Borrar todo"
  def message(:selected_items, _bindings), do: "Elementos seleccionados"
  def message(:remove_chip, %{label: label}), do: "Eliminar #{label}"
  def message(:facet_key_context, _bindings), do: "Escribiendo el nombre de una faceta"
  def message(:facet_value_context, %{facet: facet}), do: "Escribiendo un valor para #{facet}"
  def message(:free_text_context, _bindings), do: "Escribiendo texto libre"
  def message(:facet_free_value_hint, _bindings), do: "Escribe un valor y pulsa Espacio"

  def message(:facet_date_value_hint, _bindings), do: "Escribe una fecha (AAAA-MM-DD) y pulsa Espacio"

  def message(:keep_typing, _bindings), do: "Sigue escribiendo para acotar los resultados"

  def message(:facet_value_suggestions_count, %{count: 0}), do: "Sin valores coincidentes"
  def message(:facet_value_suggestions_count, %{count: 1}), do: "1 valor coincidente"

  def message(:facet_value_suggestions_count, %{count: count}), do: "#{count} valores coincidentes"

  def message(:facet_key_suggestions_count, %{count: 0}), do: "Sin facetas coincidentes"
  def message(:facet_key_suggestions_count, %{count: 1}), do: "1 faceta coincidente"
  def message(:facet_key_suggestions_count, %{count: count}), do: "#{count} facetas coincidentes"

  # Every other key keeps the canonical English string.
  def message(key, bindings), do: Flicker.Messages.English.message(key, bindings)
end
