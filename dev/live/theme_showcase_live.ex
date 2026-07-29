defmodule Dev.Live.ThemeShowcase do
  @moduledoc """
  Playground page (Spec 005 / Spec 016): the themed showcase. One view per
  shipped preset — vanilla, Tailwind, daisyUI — selected by a `?theme=` param
  and a top-right theme picker, with the whole example set rendered in that
  preset and the copyable code you'd add to adopt it (CSS for vanilla, the
  preset call for Tailwind/daisyUI).
  """

  use Phoenix.LiveView

  import Dev.UI

  alias Flicker.Theme

  @results [
    %Flicker.Result{value: "1", label: "Casey Cassidy", sublabel: "Bass"},
    %Flicker.Result{value: "2", label: "Alex Rivers", sublabel: "Drums"},
    %Flicker.Result{value: "3", label: "Jordan Blake", sublabel: "Vocals"}
  ]

  @themes [
    {"vanilla", "Vanilla"},
    {"tailwind", "Tailwind"},
    {"daisy_ui", "daisyUI"}
  ]

  @daisy_themes ~w(light dark cupcake corporate synthwave retro dracula nord)

  # Starter CSS for the framework-free `flicker-*` classes — injected so the
  # vanilla view isn't unstyled, and shown verbatim as the copyable snippet a
  # host drops into their own stylesheet.
  @vanilla_css """
  .flicker { position: relative; width: 100%; }
  .flicker-search-input,
  .flicker-multi-field {
    width: 100%; padding: 0.5rem 0.75rem;
    border: 1px solid #cbd5e1; border-radius: 0.375rem; font-size: 0.875rem;
  }
  .flicker-multi-field { display: flex; flex-wrap: wrap; align-items: center; gap: 0.375rem; }
  .flicker-multi-input { flex: 1; min-width: 6rem; border: 0; outline: none; background: none; }
  .flicker-listbox {
    position: absolute; z-index: 10; margin-top: 0.25rem; width: 100%; max-height: 15rem;
    overflow: auto; background: #fff; border: 1px solid #e2e8f0; border-radius: 0.375rem;
    box-shadow: 0 10px 15px -3px rgb(0 0 0 / 0.1); list-style: none; padding: 0.25rem 0;
  }
  .flicker-option, .flicker-suggestion {
    display: block; width: 100%; text-align: left; padding: 0.5rem 0.75rem;
    background: none; border: 0; font: inherit; cursor: pointer;
  }
  .flicker-option:hover, .flicker-suggestion:hover { background: #eef2ff; }
  .flicker-option--active { background: #e0e7ff; }
  .flicker-option-sublabel { margin-left: 0.5rem; color: #94a3b8; font-size: 0.75rem; }
  .flicker-chip {
    display: inline-flex; align-items: center; gap: 0.25rem; padding: 0.125rem 0.5rem;
    background: #eef2ff; color: #4338ca; border-radius: 9999px; font-size: 0.75rem;
  }
  .flicker-chip-remove, .flicker-clear-button, .flicker-multi-clear {
    background: none; border: 0; color: #818cf8; cursor: pointer;
  }
  .flicker-empty, .flicker-loading, .flicker-hint, .flicker-error {
    padding: 0.5rem 0.75rem; color: #64748b; font-size: 0.875rem;
  }
  """

  @impl true
  @doc "Assigns the fixed result list and the daisyUI sub-theme."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:results, @results)
      |> assign(:themes, @themes)
      |> assign(:daisy_themes, @daisy_themes)
      |> assign(:daisy_theme, "light")

    {:ok, socket}
  end

  @impl true
  @doc "Adopts the `?theme=` param (default Tailwind) — the theme picker patches it."
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    name =
      if params["theme"] in ~w(vanilla tailwind daisy_ui), do: params["theme"], else: "tailwind"

    socket =
      socket
      |> assign(:theme_name, name)
      |> assign(:theme, theme_for(name))

    {:noreply, socket}
  end

  defp theme_for("vanilla"), do: Theme.vanilla()
  defp theme_for("daisy_ui"), do: Theme.daisy_ui()
  defp theme_for(_tailwind), do: Theme.tailwind()

  @impl true
  @doc "Switches which built-in daisyUI theme the daisyUI view renders under."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("set_daisy_theme", %{"theme" => theme}, socket) when theme in @daisy_themes do
    {:noreply, assign(socket, :daisy_theme, theme)}
  end

  @impl true
  @doc "No-op: this page only renders, it doesn't track a selection."
  @spec handle_info(
          {atom(), Flicker.Result.t() | nil | [Flicker.Result.t()]},
          Phoenix.LiveView.Socket.t()
        ) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:theme_selected, _result}, socket), do: {:noreply, socket}

  @impl true
  @doc "Renders the theme picker, the examples in the chosen preset, and its adoption code."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    assigns =
      assigns
      |> assign(:vanilla_css, @vanilla_css)
      |> assign(:adoption_code, adoption_code(assigns.theme_name))
      |> assign(:adoption_lang, if(assigns.theme_name == "vanilla", do: "css", else: "elixir"))
      |> assign(:daisy?, assigns.theme_name == "daisy_ui")

    ~H"""
    <.page title="Theme showcase" current_path="/themes">
      <:description>
        The same Flicker components rendered in each shipped preset. Pick a
        theme top-right; copy the code to adopt it.
      </:description>

      <%!-- `<%= %>` with `raw/1`, not `{...}`: LiveView disables curly
      interpolation inside `<style>` and `<script>` tags, so `{@vanilla_css}`
      rendered as that literal text and the vanilla page shipped no CSS at all.
      `raw/1` because HTML-escaping would turn `>` in the selectors into
      `&gt;` and break the rules; the content is a compile-time constant, not
      user input. --%>
      <style :if={@theme_name == "vanilla"}>
        <%= Phoenix.HTML.raw(@vanilla_css) %>
      </style>

      <div class="mb-6 flex items-center justify-end gap-1 rounded-lg border border-gray-200 bg-gray-50 p-1 sm:w-fit sm:ml-auto">
        <.link
          :for={{name, label} <- @themes}
          patch={"/themes?theme=#{name}"}
          class={[
            "rounded-md px-3 py-1.5 text-sm font-medium",
            @theme_name == name && "bg-white text-indigo-700 shadow-sm",
            @theme_name != name && "text-gray-600 hover:text-gray-900"
          ]}
        >
          {label}
        </.link>
      </div>

      <div :if={@daisy?} class="mb-4">
        <form phx-change="set_daisy_theme">
          <label for="daisy-theme-picker" class="mr-2 text-sm text-gray-600">daisyUI theme</label>
          <select id="daisy-theme-picker" name="theme" class="rounded-md border border-gray-300 px-2 py-1 text-sm">
            <option :for={t <- @daisy_themes} value={t} selected={t == @daisy_theme}>{t}</option>
          </select>
        </form>
      </div>

      <div
        data-theme={@daisy? && @daisy_theme}
        class={["space-y-8", @daisy? && "rounded-lg bg-base-100 p-4"]}
      >
        <.section label="Single select">
          <Flicker.select
            id={"theme-select-#{@theme_name}"}
            source={{Flicker.Providers.Static, results: @results}}
            theme={@theme}
            on_select={:theme_selected}
          />
        </.section>

        <.section label="Multi-select">
          <Flicker.select
            id={"theme-multi-#{@theme_name}"}
            source={{Flicker.Providers.Static, results: @results}}
            theme={@theme}
            multiple
            on_select={:theme_selected}
          />
        </.section>
      </div>

      <.section label="Adopt this theme" class="mt-8">
        <.code_example id={"theme-code-#{@theme_name}"} code={@adoption_code} lang={@adoption_lang}>
          <p class="mb-1 text-sm text-gray-500">{adoption_blurb(@theme_name)}</p>
        </.code_example>
      </.section>
    </.page>
    """
  end

  defp adoption_blurb("vanilla"),
    do:
      "Vanilla ships unstyled flicker-* class names (the default) — drop this starter CSS into your stylesheet and tweak:"

  defp adoption_blurb("daisy_ui"), do: "daisyUI components — set it globally or per component:"

  defp adoption_blurb(_tailwind), do: "Tailwind utilities, no component library — set it globally or per component:"

  defp adoption_code("vanilla"), do: @vanilla_css

  defp adoption_code(name) do
    preset = if name == "daisy_ui", do: "daisy_ui", else: "tailwind"

    """
    # Globally, in config/config.exs:
    config :flicker, default_theme: Flicker.Theme.#{preset}()

    # Or per component:
    <Flicker.select theme={Flicker.Theme.#{preset}()} ... />
    """
  end
end
