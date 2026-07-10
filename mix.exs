defmodule Flicker.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/team-alembic/flicker"

  def project do
    [
      app: :flicker,
      version: @version,
      elixir: "~> 1.17",
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
      preferred_cli_env: [
        ci: :test,
        "test.coverage": :test
      ],
      usage_rules: usage_rules()
    ]
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

  defp elixirc_paths(:dev), do: ["lib", "dev"]

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
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      # `README.template.md` is the template-only file; rename.sh promotes
      # it to README.md before the first hex publish, so it isn't shipped.
      files: ~w(lib guides .formatter.exs mix.exs README.md LICENSE* CHANGELOG* usage-rules.md)
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
        {:picosat_elixir, "~> 0.2", only: [:dev, :test], runtime: false}
      ]
    end
  end

  defp tooling_deps do
    [
      # Docs
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false},

      # Test support
      {:phoenix_test, "~> 0.11", only: [:dev, :test], runtime: false},
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

      # HTTP server for the dev playground's endpoint (Spec 005) — `:dev`
      # only, never shipped and never started outside `mix dev`.
      {:bandit, "~> 1.0", only: :dev}
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
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/main/%{path}#L%{line}",
      extra_section: "GUIDES",
      extras: extras(),
      groups_for_extras: [Guides: ~r"guides/"],
      before_closing_head_tag: fn
        :html -> ~s|<link rel="icon" href="data:,">|
        _ -> ""
      end
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
