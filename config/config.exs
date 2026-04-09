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

# CollabEx Auth Pipeline — empty by default (all connections allowed).
# Configure middleware to require authentication:
#
#   config :collabex, CollabEx.Auth,
#     pipeline: [
#       {CollabEx.Auth.Middleware.JWT, secret: "your-secret", issuer: "your-app"},
#       # Or token-based:
#       # {CollabEx.Auth.Middleware.Token, lookup: &MyApp.Tokens.validate/1},
#       # Or custom function:
#       # {CollabEx.Auth.Middleware.Custom, auth_fn: &MyApp.Auth.check/2}
#     ]
config :collabex, CollabEx.Auth, pipeline: []

# CollabEx Presence — configurable disconnect cleanup timeout.
# Default: 30 seconds. After this period with no heartbeat, the user
# is removed from the room's presence list.
config :collabex_web, CollabExWeb.Presence, disconnect_timeout: 30_000

# REST API key authentication for server-to-server calls.
# Empty list = no auth required (development mode).
# In production, set via runtime config:
#   config :collabex_web, CollabExWeb.Plugs.ApiKeyAuth,
#     api_keys: [System.fetch_env!("COLLABEX_API_KEY")]
config :collabex_web, CollabExWeb.Plugs.ApiKeyAuth, api_keys: []
