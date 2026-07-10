if Code.ensure_loaded?(Igniter) do
  example = "mix igniter.install flicker"

  defmodule Mix.Tasks.Flicker.Install do
    @shortdoc "Installs Flicker and wires its colocated JS hook into the host bundle"

    @moduledoc """
    Installs Flicker into a Phoenix app.

    ## Recommended installation

        #{example}

    This fetches Flicker as a dependency and then runs this task.

    ## What it does

    1. Adds `:flicker` to the formatter's `import_deps`, so `mix format`
       picks up Flicker's `Flicker.select/1` call formatting.
    2. Adds a `config :flicker, default_limit: ..., default_debounce: ...`
       block to `config/config.exs` — only the keys not already configured.
    3. Wires the keyboard-nav colocated hook into `assets/js/app.js`: an
       `import {hooks as flickerHooks} from "phoenix-colocated/flicker"`
       and its merge into the `LiveSocket` `hooks` option, alongside the
       host's own colocated hooks.

    If step 3's patterns don't match your `app.js` (a hand-rolled bundler
    setup, for instance), a notice with the two manual edits is printed
    instead of failing.
    """

    use Igniter.Mix.Task

    @example example

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        example: @example,
        schema: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.Project.Formatter.import_dep(:flicker)
      |> configure_defaults()
      |> wire_colocated_hook()
    end

    @default_config [default_limit: 25, default_debounce: 150]

    defp configure_defaults(igniter) do
      Enum.reduce(@default_config, igniter, fn {key, value}, igniter ->
        if Igniter.Project.Config.configures_key?(igniter, "config.exs", :flicker, key) do
          igniter
        else
          Igniter.Project.Config.configure(igniter, "config.exs", :flicker, [key], value)
        end
      end)
    end

    @app_js "assets/js/app.js"
    @import_marker "phoenix-colocated/flicker"

    defp wire_colocated_hook(igniter) do
      if Igniter.exists?(igniter, @app_js) do
        igniter = Igniter.include_glob(igniter, @app_js)
        source = Rewrite.source!(igniter.rewrite, @app_js)
        content = Rewrite.Source.get(source, :content)

        if String.contains?(content, @import_marker) do
          igniter
        else
          patch_app_js(igniter, source, content)
        end
      else
        explain_manual_js_setup(igniter)
      end
    end

    defp patch_app_js(igniter, source, content) do
      with {:ok, content} <- add_import(content),
           {:ok, content} <- merge_hooks(content) do
        source = Rewrite.Source.update(source, :content, content)
        %{igniter | rewrite: Rewrite.update!(igniter.rewrite, source)}
      else
        :error -> explain_manual_js_setup(igniter)
      end
    end

    # Adds the import right after the last existing
    # `phoenix-colocated/<app>` import (the host's own colocated hooks, if
    # any), falling back to right after the `phoenix_live_view` import.
    defp add_import(content) do
      import_line = ~s|import {hooks as flickerHooks} from "#{@import_marker}"\n|

      cond do
        String.contains?(content, "phoenix-colocated/") ->
          {:ok, insert_after_last_match(content, ~r/^import .*phoenix-colocated\/.*$/m, import_line)}

        String.contains?(content, ~s|from "phoenix_live_view"|) ->
          {:ok,
           insert_after_last_match(
             content,
             ~r/^import .*from "phoenix_live_view".*$/m,
             import_line
           )}

        true ->
          :error
      end
    end

    defp insert_after_last_match(content, regex, insertion) do
      Regex.scan(regex, content)
      |> List.last()
      |> case do
        [match] ->
          [head, tail] = String.split(content, match, parts: 2)
          head <> match <> "\n" <> insertion <> tail

        _ ->
          content
      end
    end

    # Merges `...flickerHooks` into an existing `hooks: {...}` option of the
    # `new LiveSocket(...)` call; if there's no `hooks:` key yet, adds one.
    defp merge_hooks(content) do
      cond do
        Regex.match?(~r/hooks:\s*\{/, content) ->
          {:ok, Regex.replace(~r/(hooks:\s*\{)/, content, "\\1...flickerHooks, ", global: false)}

        String.contains?(content, "new LiveSocket(") ->
          {:ok,
           Regex.replace(
             ~r/(new LiveSocket\([^{]*\{)/,
             content,
             "\\1\n  hooks: {...flickerHooks},",
             global: false
           )}

        true ->
          :error
      end
    end

    defp explain_manual_js_setup(igniter) do
      Igniter.add_notice(igniter, """
      Flicker installation:

      Couldn't automatically wire the keyboard-nav colocated hook into
      #{@app_js}. Add these two edits by hand:

        import {hooks as flickerHooks} from "phoenix-colocated/flicker"

      and merge it into the `LiveSocket` hooks option:

        const liveSocket = new LiveSocket("/live", Socket, {
          hooks: {...flickerHooks},
          ...
        })
      """)
    end
  end
else
  defmodule Mix.Tasks.Flicker.Install do
    @shortdoc "Installs Flicker (requires Igniter)"

    @moduledoc """
    Installs Flicker into a Phoenix app.

    This task requires Igniter. Add it to your dependencies and try again:

        {:igniter, "~> 0.6", only: [:dev]}
    """

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'flicker.install' requires Igniter to be available.

      Add it to your dependencies and run `mix deps.get`:

          {:igniter, "~> 0.6", only: [:dev]}

      then run `mix igniter.install flicker` again.
      """)

      exit({:shutdown, 1})
    end
  end
end
