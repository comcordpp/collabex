# CollabEx

An open-source Elixir collaboration server.

CollabEx provides real-time collaboration primitives built on top of Elixir/OTP, designed for building collaborative editing, shared workspaces, and multi-user interactive applications.

## Architecture

This is an Elixir umbrella project. Individual applications live under `apps/`.

## Getting Started

### Prerequisites

- Elixir 1.16+
- Erlang/OTP 26+
- PostgreSQL 15+

### Setup

```bash
mix deps.get
mix ecto.setup
mix phx.server
```

## License

MIT License. See [LICENSE](LICENSE) for details.
