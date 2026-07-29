defmodule Flicker.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/team-alembic/flicker"

  def project do
    [
      app: :flicker,
      version: @version,
      elixir: "~> 1.17",
      # Needed for `Phoenix.LiveView.ColocatedHook`'s merged manifest
      # (`_build/#{Mix.env()}/phoenix-colocated/flicker/index.js`) to be
      # written at all — otherwise only the per-hook fragment files land in
      # `_build`, and nothing ever exports the `hooks` map a `LiveSocket`
      # needs. Real host apps normally get this for free from their own
      # Phoenix 1.8 boilerplate; flicker needs it itself for the dev
      # playground's `.Nav`/`.Palette`/`.FlickerSearchNav` hooks to mount
      # at all (Spec 005/007 — this was previously silently broken: the
      # playground rendered fine, but no client-side keyboard behaviour
      # ever ran, since `phx-hook="..."` had nothing to attach).
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :test,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      package: package(),
      description: description(),
      name: "Flicker",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: &docs/0,
      dialyzer: [
        # `:phoenix_test` — `Flicker.Test.search_select/3` calls it directly.
        plt_add_apps: [:mix, :ex_unit, :phoenix_test],
        plt_core_path: "priv/plts",
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      usage_rules: usage_rules()
    ]
  end

  def cli do
    [preferred_envs: [ci: :test, "test.coverage": :test]]
  end

  # `Dev.Application` (dev/application.ex) starts the dev playground's
  # Bandit-served endpoint (Spec 005) — wired as the `mod` callback only in
  # `:dev`, so `:test`/`:prod` builds never boot it even though `dev/` is on
  # `:test`'s `elixirc_paths` too (Spec 004's harness needs it compiled, not
  # running).
  def application do
    base = [extra_applications: [:logger]]
    if Mix.env() == :dev, do: base ++ [mod: {Dev.Application, []}], else: base
  end

  # `dev/` holds the seeded Ash demo domain (Spec 004's test harness) and the
  # dev playground built on it (Spec 005). It's Ash-dependent, so it's only
  # added to the test path when `ash` is actually in this build's deps — the
  # same `FLICKER_NO_ASH` switch `ash_deps/0` uses, so the no-ash CI leg
  # never compiles it. (Deps aren't compiled yet when `elixirc_paths/1` runs,
  # so `Code.ensure_loaded?/1` can't be used to detect this here.)
  defp elixirc_paths(:test) do
    if System.get_env("FLICKER_NO_ASH"), do: ["lib", "test/support"], else: ["lib", "test/support", "dev"]
  end

  defp elixirc_paths(:dev) do
    if System.get_env("FLICKER_NO_ASH"), do: ["lib"], else: ["lib", "dev"]
  end

  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "An Ash-native searchable select / combobox / faceted-search component for Phoenix LiveView."
  end

  defp package do
    [
      maintainers: ["Team Alembic"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "HexDocs" => "https://hexdocs.pm/flicker",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      # `README.template.md` is the template-only file; rename.sh promotes
      # it to README.md before the first hex publish, so it isn't shipped.
      files: ~w(lib guides assets .formatter.exs mix.exs README.md LICENSE* CHANGELOG* usage-rules.md)
    ]
  end

  defp deps do
    [
      # Core — the only hard runtime dependency (ADR-006, ADR-008).
      {:phoenix_live_view, "~> 1.1"}
    ] ++ ash_deps() ++ tooling_deps()
  end

  # `ash`/`ash_phoenix` are optional runtime deps (ADR-006, ADR-008): the
  # built-in `Flicker.Providers.AshResource` needs them, core does not.
  # Excluded entirely with `FLICKER_NO_ASH` set — the no-ash CI leg runs
  # `mix deps.get` with that set so `ash` never lands in its lock file,
  # forcing the `Code.ensure_loaded?/1` compile boundary to hold for real.
  defp ash_deps do
    if System.get_env("FLICKER_NO_ASH") do
      []
    else
      [
        {:ash, "~> 3.0", optional: true},
        {:ash_phoenix, "~> 2.0", optional: true},
        # SAT solver `Ash.Policy.Authorizer` needs — only our own dev/test
        # harness (the policy-bearing `Dev.Music.Artist`) uses policies, so
        # this is dev/test-only, not part of the published optional deps.
        {:picosat_elixir, "~> 0.2", only: [:dev, :test], runtime: false},
        # Optional interop target (Spec 009, ADR-006 pattern): a `Cinder`
        # table/collection can be driven by a `Flicker.search` filter via
        # query composition. Nothing under `lib/` calls `Cinder.*` directly
        # — this is dev/test-only so the playground page and its test can
        # exercise the recipe; a real host adds `cinder` itself. Lives in
        # `ash_deps/0`, not `tooling_deps/0`, because `cinder` hard-depends
        # on `ash` itself — pulling it in unconditionally would drag `ash`
        # back into the no-ash CI leg's dependency tree.
        {:cinder, "~> 0.15", optional: true, only: [:dev, :test]}
      ]
    end
  end

  defp tooling_deps do
    [
      # Docs
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false},

      # Test support
      {:phoenix_test, "~> 0.11", only: [:dev, :test], runtime: false},
      # Property-testing the query parser (Spec 003) — a direct dep so it's
      # available on the no-ash CI leg too, where `ash` (which also brings
      # `stream_data` transitively) is deliberately absent. No `:only`
      # restriction: `ash` depends on it unrestricted (`env: :prod`), and
      # Mix requires matching `:only` constraints across the dep graph.
      {:stream_data, "~> 1.0", runtime: false},
      # `mix_audit`'s `req` and `phoenix_test`'s `plug` want `mime` in
      # different envs; pin it ourselves so the two don't diverge.
      {:mime, "~> 2.0", only: [:dev, :test], override: true},

      # Quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},

      # Dev QoL
      {:mix_test_watch, "~> 1.2", only: [:dev, :test], runtime: false},
      {:doctest_formatter, "~> 0.3", only: [:dev, :test], runtime: false},

      # Formatter plugin — rewrites code based on .credo.exs rules.
      {:quokka, "~> 2.12", only: [:dev, :test], runtime: false},

      # Ash-aware Credo checks (opt-in for Ash packages). Also enable the
      # plugin in .credo.exs and switch the `lint` alias to compile before
      # credo — the compiled-introspection checks need it.
      # {:ash_credo, "~> 0.7", only: [:dev, :test], runtime: false},

      # Release automation (conventional commits -> CHANGELOG + tag)
      {:git_ops, "~> 2.6", only: [:dev, :test], runtime: false},

      # Syncs usage-rules.md from deps into AGENTS.md or agent skills.
      {:usage_rules, "~> 1.1", only: [:dev], runtime: false},

      # Needed by `mix igniter.install` (the installer, downstream), our own
      # `mix usage_rules.sync`, and the installer's tests (`:test`) —
      # optional, not a hard runtime dep.
      {:igniter, "~> 0.6", optional: true, only: [:dev, :test], runtime: false},

      # AST-based JS codemods (Rust NIF parser) — the installer uses this to
      # wire Flicker's colocated hook into `assets/js/app.js` via a real JS
      # parse (`extend_hook_object`/`insert_imports`) rather than fragile
      # regex string-patching. Optional and dev/test-only, same as igniter.
      {:igniter_js, "~> 0.4", optional: true, only: [:dev, :test], runtime: false},

      # HTTP server for the dev playground's endpoint (Spec 005) — never
      # shipped. Also `:test`-only (not started there, just compiled) so the
      # browser suite (Spec 007) can boot `Dev.Endpoint` for real over HTTP
      # instead of `Phoenix.ConnTest`'s in-process dispatch, which axe-core
      # and Wallaby both need a rendered DOM to run against.
      {:bandit, "~> 1.0", only: [:dev, :test]},

      # The dev playground has no asset pipeline, so nothing else would notice
      # an edit to `dev/` or `lib/flicker/`: `mix dev` is a plain
      # `run --no-halt`, and a long-running server otherwise serves stale
      # markup indefinitely (which has already cost us two phantom
      # regressions). `:dev` only — the same endpoint is booted in `:test` by
      # Spec 007's browser suite, which must not recompile mid-request.
      {:phoenix_live_reload, "~> 1.5", only: :dev},

      # Browser-driven tests (Spec 007): axe-core accessibility scans and
      # client-side keyboard behaviour ExUnit/PhoenixTest can't reach (real
      # arrow-key/aria-activedescendant/focus-trap DOM behaviour). `a11y_audit`
      # vendors axe-core itself — no npm — and drives it through a Wallaby
      # session. `:test`-only, tagged `@moduletag :browser` and excluded from
      # the default `mix test` run (see `.github/workflows/elixir.yml`'s
      # `browser` job and `test/support/browser_case.ex`).
      {:a11y_audit, "~> 0.4", only: :test, runtime: false},
      {:wallaby, "~> 0.30", only: :test, runtime: false}
    ]
  end

  defp aliases do
    [
      ci: [
        "deps.unlock --check-unused",
        "format --check-formatted",
        "credo --strict",
        "doctor --full --raise",
        "sobelow --config",
        "hex.audit",
        "deps.audit",
        "dialyzer",
        "test"
      ],
      credo: ["credo --strict"],
      # If you enable ash_credo, use `mix lint` instead of `mix credo` — the
      # compiled-introspection checks need modules to be compiled first.
      lint: ["compile", "credo --strict"],
      sobelow: ["sobelow --config"],
      # Starts the dev playground (Spec 005): seeded `Dev.Music` domain,
      # Bandit-served endpoint, no database.
      dev: ["run --no-halt"]
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/flicker-logo.png",
      favicon: "assets/flicker-logo.png",
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/%{path}#L%{line}",
      filter_modules: ~r/^Elixir\.(Flicker|Mix\.Tasks\.Flicker\.)/,
      skip_code_autolink_to: &String.starts_with?(&1, "Dev."),
      extra_section: "GUIDES",
      extras: extras(),
      groups_for_extras: [
        "Getting started": ["guides/getting-started.md"],
        Concepts: [
          "guides/providers.md",
          "guides/theming.md"
        ],
        Features: [
          "guides/faceted-search.md",
          "guides/command-palette.md"
        ],
        Accessibility: ["guides/accessibility.md"],
        Integrations: ["guides/cinder-integration.md"]
      ],
      groups_for_modules: [
        "Public API": [
          Flicker,
          Flicker.Facet,
          Flicker.Messages,
          Flicker.Provider,
          Flicker.Query,
          Flicker.Result,
          Flicker.Theme
        ],
        Providers: [
          Flicker.Providers.AshResource,
          Flicker.Providers.Static
        ],
        Integrations: [
          Flicker.AshPhoenixForm,
          Flicker.Integrations.Cinder
        ],
        Testing: [Flicker.Test],
        "Mix tasks": [Mix.Tasks.Flicker.Install],
        "Component internals": ~r/^Flicker\.(Components|CursorContext|FacetSuggest|Keyboard|Messages\.English)/
      ]
    ]
  end

  defp extras do
    ["README.md", "CHANGELOG.md", "usage-rules.md"] ++
      Path.wildcard("guides/**/*.{md,cheatmd,livemd}")
  end

  # `mix usage_rules.sync` materialises this config into committed
  # `.claude/skills/*/SKILL.md` files. Re-run after adding or removing deps.
  defp usage_rules do
    [
      skills: [
        location: ".claude/skills",

        # Auto-generate a `use-<pkg>` skill per listed dependency. Each skill
        # references that package's shipped `usage-rules.md` (if any).
        deps: [
          # :ash, :phoenix, :ecto, :req,
          # ~r/^ash_/,
        ],

        # Pre-built skills shipped by packages in their `usage-rules/skills/`
        # directory — opt in per package.
        package_skills: [
          # :ash, ~r/^ash_/,
        ],

        # Custom composed skills that pull rules from multiple deps and
        # ship them as a single SKILL.md.
        build: [
          # "ash-framework": [
          #   description: "Use when working with Ash Framework or any of its extensions.",
          #   usage_rules: [:ash, ~r/^ash_/]
          # ],
          # "phoenix-framework": [
          #   description: "Use when working with Phoenix — controllers, LiveViews, routes, views.",
          #   usage_rules: [:phoenix, ~r/^phoenix_/]
          # ]
        ]
      ]
    ]
  end
end
