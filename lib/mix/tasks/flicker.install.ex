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
    3. Wires the keyboard-nav colocated hook into `assets/js/app.js` using
       `igniter_js`'s AST codemods: an
       `import {hooks as flickerHooks} from "phoenix-colocated/flicker"`
       and a `...flickerHooks` spread merged into the `LiveSocket` `hooks`
       option, alongside the host's own colocated hooks.

    If step 3 can't parse your `app.js` or find a `LiveSocket` (a
    hand-rolled bundler setup, for instance), a notice with the two manual
    edits is printed instead of failing.

    4. Registers Flicker's templates as a Tailwind source so its utility
       classes aren't purged. On a Tailwind v4 setup (an `@import
       "tailwindcss"` in `assets/css/app.css`) this adds an
       `@source "../../deps/flicker";` directive; on a v3 setup (a
       `content: [...]` array in `assets/tailwind.config.js`) it adds a
       `"../deps/flicker/**/*.*ex"` glob to that array.

    If neither is found, a notice with the manual edit is printed instead.

    Pass `--daisyui` to also add a `@plugin "daisyui";` directive to a
    Tailwind v4 `app.css`, for hosts using `Flicker.Theme.daisy_ui()`. Off
    by default — daisyUI is an opt-in preset, not a Flicker requirement.
    """

    use Igniter.Mix.Task

    @example example

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        example: @example,
        # `--daisyui` opts a Tailwind v4 host into the daisyUI plugin, for
        # hosts that use `Flicker.Theme.daisy_ui()`. Off by default: daisyUI
        # is one opt-in preset, not a Flicker requirement (ADR-002).
        schema: [daisyui: :boolean]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.Project.Formatter.import_dep(:flicker)
      |> configure_defaults()
      |> wire_colocated_hook()
      |> wire_tailwind_source()
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
    @import_line ~s|import {hooks as flickerHooks} from "phoenix-colocated/flicker"|

    @parser IgniterJs.Parsers.Javascript.Parser
    # `igniter_js` is an optional dep, so it's absent when Flicker compiles
    # as a dependency of a host that doesn't have it. The calls below are
    # runtime-guarded by `Code.ensure_loaded?/1`, so the compiler's
    # undefined-function warning is a false positive — silence it.
    @compile {:no_warn_undefined, @parser}

    defp wire_colocated_hook(igniter) do
      cond do
        not Igniter.exists?(igniter, @app_js) ->
          explain_manual_js_setup(igniter)

        not Code.ensure_loaded?(@parser) ->
          # `igniter_js` is an optional dep — it isn't pulled into a host app
          # just by depending on Flicker. Declare it (dev-only, compile-time)
          # and ask for a re-run so the AST codemods below can wire `app.js`.
          igniter
          |> Igniter.Project.Deps.add_dep({:igniter_js, "~> 0.4", only: [:dev], runtime: false})
          |> Igniter.add_notice("""
          Flicker installation:

          The `app.js` hook wiring needs `igniter_js` (added to your deps just
          now). Run `mix deps.get`, then re-run `mix flicker.install` to
          finish wiring #{@app_js}.
          """)

        true ->
          igniter = Igniter.include_glob(igniter, @app_js)
          source = Rewrite.source!(igniter.rewrite, @app_js)
          content = Rewrite.Source.get(source, :content)

          if String.contains?(content, @import_marker) do
            igniter
          else
            patch_app_js(igniter, source, content)
          end
      end
    end

    # Patches `app.js` through `igniter_js`'s AST codemods rather than regex:
    # `insert_imports/2` adds the colocated-hook import, and
    # `extend_hook_object/2` spreads `...flickerHooks` into the `LiveSocket`
    # `hooks:` option (adding the `hooks:` key if the call doesn't have one).
    # Both round-trip the file through the JS parser, so the written result
    # is reformatted by the parser's printer — expected, and shown in the
    # Igniter diff for the user to approve. Any parse/shape failure (a
    # hand-rolled bundler setup with no `LiveSocket`, say) returns `:error`
    # and we fall back to printing the manual edits.
    defp patch_app_js(igniter, source, content) do
      with {:ok, _fun, content} <- @parser.insert_imports(content, @import_line),
           {:ok, _fun, content} <- @parser.extend_hook_object(content, "...flickerHooks") do
        source = Rewrite.Source.update(source, :content, content)
        %{igniter | rewrite: Rewrite.update!(igniter.rewrite, source)}
      else
        {:error, _fun, _reason} -> explain_manual_js_setup(igniter)
      end
    end

    @app_css "assets/css/app.css"
    @tailwind_config "assets/tailwind.config.js"
    @source_marker "deps/flicker"
    # Relative to `app.css` (assets/css/) for the v4 `@source`, and to the
    # config's own dir (assets/) for the v3 `content` glob.
    @v4_source ~s|@source "../../deps/flicker";|
    @v3_content_glob ~s|"../deps/flicker/**/*.*ex"|
    @daisyui_plugin ~s|@plugin "daisyui";|

    # Registers Flicker's shipped templates (`deps/flicker/lib`) with
    # Tailwind so its utility classes survive the content purge. Tailwind v4
    # (an `@import "tailwindcss"` in `app.css`) takes an `@source` directive;
    # v3 (a `content: [...]` array in `tailwind.config.js`) takes a glob in
    # that array. Both are plain-text inserts guarded for idempotency; if
    # neither setup is recognised a manual notice is printed.
    #
    # With `--daisyui`, a v4 host also gets a `@plugin "daisyui";` directive
    # (for `Flicker.Theme.daisy_ui()`); off by default so Flicker never
    # forces a CSS framework on a host that didn't ask (ADR-002).
    defp wire_tailwind_source(igniter) do
      cond do
        tailwind_v4?(igniter) -> add_v4_source(igniter)
        tailwind_v3?(igniter) -> add_v3_content_glob(igniter)
        true -> explain_manual_tailwind_setup(igniter)
      end
    end

    defp daisyui?(igniter), do: igniter.args.options[:daisyui] == true

    defp tailwind_v4?(igniter) do
      case read_file(igniter, @app_css) do
        {:ok, content} -> Regex.match?(~r/@import\s+["']tailwindcss["']/, content)
        :error -> false
      end
    end

    defp tailwind_v3?(igniter) do
      case read_file(igniter, @tailwind_config) do
        {:ok, content} -> Regex.match?(~r/content:\s*\[/, content)
        :error -> false
      end
    end

    defp add_v4_source(igniter) do
      igniter =
        patch_file(igniter, @app_css, fn content ->
          cond do
            String.contains?(content, @source_marker) ->
              {:ok, content}

            # After the last existing `@source` line, if any…
            Regex.match?(~r/^\s*@source\b.*$/m, content) ->
              {:ok, insert_after_last_match(content, ~r/^\s*@source\b.*$/m, @v4_source <> "\n")}

            # …otherwise right after the `@import "tailwindcss"` line.
            true ->
              {:ok,
               insert_after_last_match(
                 content,
                 ~r/^\s*@import\s+["']tailwindcss["'].*$/m,
                 @v4_source <> "\n"
               )}
          end
        end)

      if daisyui?(igniter), do: add_daisyui_plugin(igniter), else: igniter
    end

    # `@plugin` directives sit with the Tailwind import; add ours right after
    # it when `--daisyui` is passed and daisyUI isn't already loaded.
    defp add_daisyui_plugin(igniter) do
      patch_file(igniter, @app_css, fn content ->
        if Regex.match?(~r/@plugin\s+["'][^"']*daisyui/, content) do
          {:ok, content}
        else
          {:ok,
           insert_after_last_match(
             content,
             ~r/^\s*@import\s+["']tailwindcss["'].*$/m,
             @daisyui_plugin <> "\n"
           )}
        end
      end)
    end

    defp add_v3_content_glob(igniter) do
      patch_file(igniter, @tailwind_config, fn content ->
        if String.contains?(content, @source_marker) do
          {:ok, content}
        else
          {:ok, Regex.replace(~r/(content:\s*\[)/, content, "\\1\n    #{@v3_content_glob},", global: false)}
        end
      end)
    end

    defp read_file(igniter, path) do
      if Igniter.exists?(igniter, path) do
        igniter = Igniter.include_glob(igniter, path)
        source = Rewrite.source!(igniter.rewrite, path)
        {:ok, Rewrite.Source.get(source, :content)}
      else
        :error
      end
    end

    defp patch_file(igniter, path, fun) do
      igniter = Igniter.include_glob(igniter, path)
      source = Rewrite.source!(igniter.rewrite, path)
      content = Rewrite.Source.get(source, :content)

      case fun.(content) do
        {:ok, ^content} ->
          igniter

        {:ok, updated} ->
          source = Rewrite.Source.update(source, :content, updated)
          %{igniter | rewrite: Rewrite.update!(igniter.rewrite, source)}
      end
    end

    defp insert_after_last_match(content, regex, insertion) do
      case List.last(Regex.scan(regex, content)) do
        [match | _] ->
          [head, tail] = String.split(content, match, parts: 2)
          head <> match <> "\n" <> insertion <> tail

        _ ->
          content
      end
    end

    defp explain_manual_tailwind_setup(igniter) do
      Igniter.add_notice(igniter, """
      Flicker installation:

      Couldn't find a Tailwind setup to register Flicker's templates with.
      So Flicker's utility classes aren't purged, add its source by hand.

      Tailwind v4 — in #{@app_css}:

        #{@v4_source}

      Tailwind v3 — in the `content` array of #{@tailwind_config}:

        #{@v3_content_glob}
      """)
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
