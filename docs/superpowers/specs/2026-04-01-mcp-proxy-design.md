# MCP Proxy — Design Spec

## Problem

Many MCP servers exist only as stdio transports. Remote clients (Claude Desktop on sandbox/cowork machines, other SSE-capable clients) cannot consume stdio directly. There is no simple, self-hosted way to expose multiple stdio MCP servers as authenticated SSE endpoints from a single VPS.

## Solution

A Docker Compose setup on a VPS that uses `mcp-proxy` (Python, server mode) to bridge stdio MCP servers to SSE/Streamable HTTP endpoints, fronted by Traefik for TLS and bearer token authentication.

## Architecture

### Request Flow

```
Client SSE remoto
  → HTTPS (Traefik, TLS via Let's Encrypt)
    → traefik-plugin-apikey (bearer token check)
      → mcp-proxy :8080 (server mode)
        → stdio child process (e.g. parcel-tracking-mcp)
```

### Components

1. **Traefik** — Reverse proxy, TLS termination (Let's Encrypt), bearer token auth via `traefik-plugin-apikey`. Configuration entirely via Docker labels, no static config files.

2. **mcp-proxy** — Custom Docker image extending `ghcr.io/sparfenyuk/mcp-proxy` with Node.js added. Runs in server mode with `--named-server-config` pointing to `servers.json`. Each named server spawns a stdio child process and exposes it at `/servers/<NAME>/sse` and `/servers/<NAME>/mcp`.

### Endpoints

| Path | Transport | Description |
|------|-----------|-------------|
| `https://{DOMAIN}/servers/parcel/sse` | SSE | parcel-tracking MCP server |
| `https://{DOMAIN}/servers/parcel/mcp` | Streamable HTTP | parcel-tracking MCP server (alt) |
| `https://{DOMAIN}/status` | HTTP | Health check |

All endpoints except `/status` require `Authorization: Bearer <token>` header.

## File Structure

```
mcp-proxy/
├── docker-compose.yml       # Traefik + mcp-proxy services
├── .env                     # DOMAIN, BEARER_TOKEN, TRACKING_API_TOKEN
├── .env.example             # Template without values
├── .gitignore               # .env, acme.json
├── Dockerfile               # mcp-proxy base + Node.js + entrypoint
├── entrypoint.sh            # Generates config.json from env vars, exec mcp-proxy
└── servers.json             # Named server config for mcp-proxy
```

## Configuration

### `.env`

| Variable | Purpose |
|----------|---------|
| `DOMAIN` | Hostname for Traefik (e.g. `mcp.example.com`) |
| `BEARER_TOKEN` | API key for client authentication |
| `TRACKING_API_TOKEN` | 17track API key for parcel-tracking-mcp |

### `servers.json`

```json
{
  "mcpServers": {
    "parcel": {
      "command": "parcel-tracking-mcp-server",
      "args": []
    }
  }
}
```

### `Dockerfile`

Extends `ghcr.io/sparfenyuk/mcp-proxy:latest`. Adds:
- Node.js runtime (for npx-based MCP servers)
- `entrypoint.sh` and `servers.json`

### `entrypoint.sh`

1. Pre-installs `parcel-tracking-mcp-server` globally via `npm install -g` at container startup (avoids npx download-on-demand, makes the path predictable)
2. Reads `TRACKING_API_TOKEN` from environment
3. Writes `config.json` into the global node_modules directory where `index.mjs` lives (the package reads config via `__dirname`, not `cwd` — path is predictable with global install)
4. Execs `mcp-proxy --host 0.0.0.0 --port 8080 --named-server-config /app/servers.json`

Note: `servers.json` should reference the globally installed binary (e.g. `"command": "parcel-tracking-mcp-server"`) rather than `npx`, since the package is pre-installed.

### Traefik (via Docker labels)

- `traefik-plugin-apikey` middleware checks `Authorization: Bearer <token>`
- TLS via Let's Encrypt with ACME HTTP challenge
- Routes `https://{DOMAIN}/*` to mcp-proxy:8080

## Authentication

- **Mechanism:** `traefik-plugin-apikey` Traefik plugin
- **Token source:** `BEARER_TOKEN` from `.env`, passed to Traefik via environment
- **Client sends:** `Authorization: Bearer <token>` header on every request
- **Health check (`/status`):** unauthenticated

## Initial MCP Server: parcel-tracking-mcp

- **npm package:** `parcel-tracking-mcp-server`
- **Runtime:** Node.js
- **Config:** `config.json` with `{ "apiToken": "<17track API key>" }` — must be placed in same directory as `index.mjs` (uses `__dirname`)
- **Tools exposed:** `search-carrier` (fuzzy search carriers), `tracking-delivery` (track parcel by number + carrier ID)

## Extensibility

Adding a new MCP server:

1. Add entry to `servers.json` with command and args
2. If it needs a runtime not in the Dockerfile (e.g. Python), add it to the Dockerfile
3. If it needs config/env vars, add to `.env` and handle in `entrypoint.sh`
4. Rebuild and restart: `docker compose up -d --build`

## Client Configuration Example

Claude Desktop (or any SSE-capable MCP client) connects directly to the SSE endpoint:

```
URL: https://mcp.example.com/servers/parcel/sse
Headers: Authorization: Bearer <token>
```

No local `mcp-proxy` installation needed on the client side.
