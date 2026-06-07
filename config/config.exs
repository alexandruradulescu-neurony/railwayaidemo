# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :showcase,
  ecto_repos: [Showcase.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :showcase, ShowcaseWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ShowcaseWeb.ErrorHTML, json: ShowcaseWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Showcase.PubSub,
  live_view: [signing_salt: "yDlkl/FM"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :showcase, Showcase.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  showcase: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  showcase: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Ash
config :showcase,
  ash_domains: [Showcase.Common]

config :ash, :default_belongs_to_type, :integer

# Oban
config :showcase, Oban,
  engine: Oban.Engines.Basic,
  repo: Showcase.Repo,
  queues: [
    order_flow: 5,
    recruit_flow: 5,
    planogram: 5,
    invoice_approval: 5,
    restaurant_compliance: 5
  ],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron, crontab: []}
  ]

config :showcase, :anthropic_client_impl, Showcase.Common.AnthropicClient.Live

# Default Claude model for text-only demos. Overridden at runtime by
# ANTHROPIC_MODEL_DEFAULT (see config/runtime.exs). Planogram vision
# stays pinned to Sonnet — see lib/showcase/planogram/impl/vision_request.ex.
config :showcase,
  anthropic_default_model: "claude-haiku-4-5-20251001"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
