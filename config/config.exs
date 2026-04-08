import Config

config :collabex_web, CollabExWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: CollabExWeb.ErrorJSON]],
  pubsub_server: CollabExWeb.PubSub,
  server: true,
  http: [port: 4000]

config :collabex_web, :generators,
  context_app: :collabex

config :phoenix, :json_library, Jason

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
