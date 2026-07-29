defmodule Flicker.NoHardcodedTextTest do
  @moduledoc """
  Spec 007's auditable-inventory criterion: *"all announcement strings resolve
  through the messages module — a grep for user-facing literals in templates
  finds none"*.

  That criterion was written as a grep a human would run, which means nobody
  ran it. This is the grep, as a test — so the `Flicker.Messages` key list stays
  the complete inventory of user-facing text (ADR-009) rather than drifting the
  moment someone adds a control with a label.

  The check is deliberately narrow: it looks for string literals in the two
  places user-facing text actually escapes review — `aria-label` and the
  label maps components pass into editors — rather than trying to judge every
  string in the codebase.
  """

  use ExUnit.Case, async: true

  @component_files [
    "lib/flicker/components/select.ex",
    "lib/flicker/components/search.ex",
    "lib/flicker/components/palette.ex",
    "lib/flicker/facet_editor/calendar.ex",
    "lib/flicker/facet_editor/dial.ex",
    "lib/flicker/facet_editor/set.ex",
    "lib/flicker/facet_editor/switch.ex"
  ]

  # `flicker-sr-only` is a class name, not prose; `aria-label={@...}` and
  # `aria-label={message(...)}` are the correct forms.
  @literal_aria_label ~r/aria-label=\{"[^"]+"\}/

  describe "aria-label never carries a bare literal" do
    test "every aria-label resolves through an assign or the messages module" do
      for file <- @component_files do
        source = File.read!(file)
        offenders = Regex.scan(@literal_aria_label, source)

        assert offenders == [],
               "#{file} has a hardcoded aria-label: #{inspect(offenders)}. " <>
                 "Route it through Flicker.Messages (ADR-009)."
      end
    end
  end

  describe "the editor label maps resolve through messages" do
    test "no component hands an editor a bare English literal" do
      # The `labels:` map is how a component names an editor's controls. Every
      # value must be a `message(...)` call, since those strings are as
      # user-facing as anything in a template.
      source = File.read!("lib/flicker/components/search.ex")

      case Regex.run(~r/labels: %\{(.*?)\n      \},/s, source) do
        nil ->
          flunk("expected a labels: map in search.ex — has the editor assign shape changed?")

        [_, body] ->
          refute body =~ ~r/:\s*"[^"]+"/,
                 "search.ex passes a hardcoded editor label: #{inspect(body)}"
      end
    end
  end

  describe "the message inventory covers every key the components ask for" do
    test "every message/2 key used in a component is implemented by English" do
      keys =
        @component_files
        |> Enum.flat_map(fn file ->
          file
          |> File.read!()
          # The negative lookbehind matters: without it this also matches
          # `context_message(assigns, :text)`, whose `:text` is a cursor-context
          # tag rather than a message key.
          |> then(&Regex.scan(~r/(?<![a-z_])message\(assigns,\s*:([a-z_?]+)/, &1))
          |> Enum.map(fn [_, key] -> String.to_atom(key) end)
        end)
        |> Enum.uniq()

      refute keys == [], "found no message/2 calls — has the helper been renamed?"

      for key <- keys do
        rendered = Flicker.Messages.get(nil, key, sample_bindings())

        assert is_binary(rendered) and rendered != "",
               "#{inspect(key)} is used by a component but renders #{inspect(rendered)}"
      end
    end
  end

  # A superset of every binding any message takes, so one call site can
  # exercise them all.
  defp sample_bindings do
    %{
      count: 2,
      label: "Casey",
      key: :status,
      chord: "⌘K",
      min_chars: 2,
      max: 5,
      min: 0,
      total: 10,
      facet: "Status",
      values: [:a, :b],
      message: "nope",
      value: "x"
    }
  end
end
