# CollabEx

An open-source Elixir collaboration server for real-time document editing. Built on Elixir/OTP and the BEAM, CollabEx provides Yjs/CRDT-compatible real-time sync over WebSockets, pluggable persistence, presence tracking, and a REST API for room management.

## Architecture

CollabEx is an Elixir umbrella project with two OTP applications:

| App | Purpose |
|-----|---------|
| `collabex` | Core collaboration engine — room lifecycle, Yjs CRDT sync, persistence adapters, auth pipeline, telemetry |
| `collabex_web` | Phoenix web layer — WebSocket transport, REST API, presence tracking, Prometheus metrics |

```
                         ┌──────────────────────────────┐
                         │     Phoenix Endpoint          │
                         │     (localhost:4000)           │
                         └────────────┬─────────────────┘
                                      │
                    ┌─────────────────┼─────────────────┐
                    │                 │                   │
              WebSocket           REST API           Prometheus
            /collabex          /api/rooms/*           /metrics
                    │                 │
                    ▼                 ▼
              RoomChannel       RoomController
           (Yjs sync proto)    (CRUD + export)
                    │                 │
                    └────────┬───────┘
                             │
                    ┌────────▼────────┐
                    │  Room.Server    │ ← GenServer per room
                    │  (via Registry) │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
         Persistence     Presence      Telemetry
        (PostgreSQL)   (Phoenix)     (Prometheus)
```

### Key Modules

| Module | Purpose |
|--------|---------|
| `CollabEx.Room.Manager` | Room lifecycle (create, lookup, list, stop) via DynamicSupervisor |
| `CollabEx.Room.Server` | GenServer per room — document state, connected clients, idle/empty timeouts |
| `CollabEx.Document.Persistence` | Behaviour for persistence adapters |
| `CollabEx.Document.Adapters.Postgres` | PostgreSQL adapter with update compaction |
| `CollabEx.Auth` | Pluggable authentication pipeline for WebSocket connections |
| `CollabEx.Auth.Middleware.JWT` | JWT token validation middleware |
| `CollabEx.Auth.Middleware.Token` | Simple token-based auth middleware |
| `CollabEx.Auth.Middleware.Custom` | Custom function-based auth middleware |
| `CollabEx.Telemetry` | Telemetry events and Prometheus metric definitions |
| `CollabExWeb.RoomChannel` | Phoenix Channel implementing Yjs sync protocol v1 |
| `CollabExWeb.RoomSocket` | WebSocket transport with auth pipeline integration |
| `CollabExWeb.Presence` | Phoenix Presence for user tracking (cursor, name, color) |
| `CollabExWeb.RoomController` | REST API for room management and document import/export |
| `CollabExWeb.Plugs.ApiKeyAuth` | Bearer token auth for protected REST endpoints |

## Prerequisites

- **Elixir** >= 1.16
- **Erlang/OTP** >= 26
- **PostgreSQL** >= 15

Verify your installation:

```bash
elixir --version    # Should show Elixir 1.16+
psql --version      # Should show 15+
```

## Getting Started

### 1. Install Dependencies

```bash
mix deps.get
```

### 2. Set Up the Database

CollabEx uses PostgreSQL for document persistence. Configure your database connection in `config/config.exs` or via environment variables. The default configuration expects a local PostgreSQL instance.

```bash
# Create the database and run migrations
mix ecto.setup
```

This creates two tables:
- `collabex_documents` — stores document state (room_id, binary state, update count)
- `collabex_document_updates` — append-only update log for incremental sync

### 3. Start the Server

```bash
mix phx.server
```

Or start with an interactive Elixir shell:

```bash
iex -S mix phx.server
```

The server starts on [http://localhost:4000](http://localhost:4000).

### 4. Connect a Yjs Client

Point any Yjs WebSocket provider at the CollabEx endpoint:

```javascript
import * as Y from 'yjs'
import { WebsocketProvider } from 'y-websocket'

const doc = new Y.Doc()
const provider = new WebsocketProvider(
  'ws://localhost:4000/collabex/websocket',
  'my-room-id',
  doc
)
```

Rooms are created automatically on first connection and terminate after 30 minutes of being empty.

## REST API

CollabEx exposes a REST API for room management. In development, no authentication is required. In production, set API keys in your configuration.

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/api/rooms` | Public | List all active rooms |
| `GET` | `/api/rooms/:room_id` | Public | Room info with presence data |
| `GET` | `/api/rooms/:room_id/presence` | Public | List connected users |
| `GET` | `/api/rooms/:room_id/document` | Protected | Export document state (base64 or binary) |
| `POST` | `/api/rooms/:room_id/document` | Protected | Import document state |
| `DELETE` | `/api/rooms/:room_id` | Protected | Delete a room |
| `GET` | `/metrics` | Public | Prometheus metrics |

### Example: List Active Rooms

```bash
curl http://localhost:4000/api/rooms
```

### Example: Export a Document

```bash
# With API key auth (production)
curl -H "Authorization: Bearer YOUR_API_KEY" \
  http://localhost:4000/api/rooms/my-room/document

# Without auth (development, default config)
curl http://localhost:4000/api/rooms/my-room/document
```

## Running Tests

### Full Test Suite

```bash
mix test
```

### Running Specific Tests

```bash
# Run tests for the core app only
mix test apps/collabex/test

# Run tests for the web app only
mix test apps/collabex_web/test

# Run a single test file
mix test apps/collabex/test/collabex/auth_test.exs

# Run with verbose output
mix test --trace
```

### Test Categories

| Category | Files | What They Cover |
|----------|-------|-----------------|
| **Auth Pipeline** | `collabex/auth_test.exs` | Empty pipeline, middleware chaining, failure handling |
| **JWT Auth** | `collabex/auth/middleware/jwt_test.exs` | JWT signature validation, claims |
| **Token Auth** | `collabex/auth/middleware/token_test.exs` | Simple token-based auth |
| **Custom Auth** | `collabex/auth/middleware/custom_test.exs` | Custom function auth |
| **Telemetry** | `collabex/telemetry_test.exs` | Metric definitions and events |
| **REST API** | `collabex_web/controllers/room_controller_test.exs` | Room CRUD, document import/export |
| **API Key Auth** | `collabex_web/plugs/api_key_auth_test.exs` | Dev mode, missing/invalid/valid keys |
| **WebSocket** | `collabex_web/channels/room_channel_test.exs` | Channel join, presence, sync messages |
| **Presence** | `collabex_web/presence_test.exs` | User tracking and metadata |

## Configuration

All configuration lives in `config/config.exs`. Key settings:

### WebSocket

```elixir
# Socket path and timeout
config :collabex_web, CollabExWeb.Endpoint,
  url: [host: "localhost"],
  http: [port: 4000]
# WebSocket at /collabex with 45-second timeout
```

### Authentication (WebSocket)

```elixir
# Default: empty pipeline (all connections allowed)
config :collabex, CollabEx.Auth,
  pipeline: []

# Production example with JWT:
config :collabex, CollabEx.Auth,
  pipeline: [
    {CollabEx.Auth.Middleware.JWT, secret: "your-secret", issuer: "your-app"}
  ]
```

### REST API Authentication

```elixir
# Default: empty list (no auth required in dev)
config :collabex_web, CollabExWeb.Plugs.ApiKeyAuth,
  api_keys: []

# Production:
config :collabex_web, CollabExWeb.Plugs.ApiKeyAuth,
  api_keys: [System.get_env("COLLABEX_API_KEY")]
```

### Presence

```elixir
# Disconnect timeout (default: 30 seconds)
config :collabex_web, CollabExWeb.Presence,
  disconnect_timeout: 30_000
```

### Room Timeouts

Rooms are managed by `CollabEx.Room.Server` with these defaults:
- **Idle timeout:** 5 minutes (room hibernates)
- **Empty timeout:** 30 minutes (room terminates when no clients connected)

### Document Persistence

```elixir
# PostgreSQL adapter with compaction after 100 updates
config :collabex, CollabEx.Document.Adapters.Postgres,
  repo: CollabEx.Repo,
  compaction_threshold: 100
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | *(local PostgreSQL)* | Ecto database connection string |
| `MIX_ENV` | `dev` | Elixir environment (`dev`, `test`, `prod`) |
| `COLLABEX_API_KEY` | *(none)* | API key for protected REST endpoints (production) |
| `SECRET_KEY_BASE` | *(none)* | Phoenix secret for production (generate with `mix phx.gen.secret`) |
| `PHX_HOST` | `localhost` | Phoenix host binding |
| `PORT` | `4000` | HTTP port |

## Monitoring

CollabEx exports Prometheus metrics at `/metrics`. Available metrics:

| Metric | Type | Description |
|--------|------|-------------|
| `collabex_room_created_total` | Counter | Total rooms created |
| `collabex_room_terminated_total` | Counter | Total rooms terminated |
| `collabex_client_connected_total` | Counter | Total client connections |
| `collabex_client_disconnected_total` | Counter | Total client disconnections |
| `collabex_sync_message_processed` | Counter | Sync messages processed |
| `collabex_document_persisted` | Counter | Document persistence events |
| `collabex_document_loaded` | Counter | Document load events |
| `collabex_room_memory` | Gauge | Room memory usage |

A Grafana dashboard is included at `grafana/collabex-dashboard.json`. Import it into your Grafana instance for real-time panels showing active rooms and connections.

### Grafana Setup

```bash
# Import the dashboard into Grafana
# 1. Open Grafana → Dashboards → Import
# 2. Upload grafana/collabex-dashboard.json
# 3. Select your Prometheus data source
```

## Code Quality

```bash
# Format code
mix format

# Check formatting (CI-friendly)
mix format --check-formatted

# Compile with warnings as errors
mix compile --warnings-as-errors
```

## Project Structure

```
collabex/
├── config/
│   └── config.exs              # All configuration
├── apps/
│   ├── collabex/               # Core collaboration engine
│   │   ├── lib/
│   │   │   └── collabex/
│   │   │       ├── application.ex        # OTP supervisor
│   │   │       ├── auth.ex               # Auth pipeline
│   │   │       ├── auth/middleware/       # JWT, Token, Custom
│   │   │       ├── document/
│   │   │       │   ├── persistence.ex    # Persistence behaviour
│   │   │       │   ├── adapters/         # PostgreSQL adapter
│   │   │       │   └── schema/           # Ecto schemas
│   │   │       ├── room/
│   │   │       │   ├── manager.ex        # Room lifecycle
│   │   │       │   └── server.ex         # GenServer per room
│   │   │       ├── repo.ex               # Ecto repo
│   │   │       └── telemetry.ex          # Metrics
│   │   ├── priv/repo/migrations/         # Database migrations
│   │   └── test/                         # Core tests
│   └── collabex_web/           # Phoenix web layer
│       ├── lib/
│       │   └── collabex_web/
│       │       ├── application.ex        # Web supervisor
│       │       ├── endpoint.ex           # Phoenix endpoint
│       │       ├── router.ex             # Routes
│       │       ├── channels/
│       │       │   ├── room_socket.ex    # WebSocket transport
│       │       │   └── room_channel.ex   # Yjs sync protocol
│       │       ├── controllers/
│       │       │   └── room_controller.ex # REST API
│       │       ├── plugs/
│       │       │   └── api_key_auth.ex   # API key auth
│       │       └── presence.ex           # Phoenix Presence
│       └── test/                         # Web tests
├── grafana/
│   └── collabex-dashboard.json # Prometheus dashboard
├── mix.exs                     # Umbrella project config
└── LICENSE                     # MIT License
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `(Postgrex.Error) FATAL: database does not exist` | Run `mix ecto.create` |
| Port 4000 already in use | `PORT=4001 mix phx.server` or kill the process on 4000 |
| `(Postgrex.Error) FATAL: password authentication failed` | Check PostgreSQL credentials in `config/config.exs` or set `DATABASE_URL` |
| WebSocket connection refused | Verify the server is running and connect to `ws://localhost:4000/collabex/websocket` |
| Tests failing with database errors | Run `MIX_ENV=test mix ecto.setup` to create the test database |
| Room not persisting after restart | Ensure PostgreSQL adapter is configured and migrations have run |

## License

MIT License. See [LICENSE](LICENSE) for details.
