# MCP Proxy

> Personal project — Docker Compose setup to expose stdio-only MCP servers as authenticated SSE endpoints from a self-hosted VPS.

## What it does

Many MCP servers only support stdio transport and cannot be consumed by remote clients directly. This project wraps them with [mcp-proxy](https://github.com/sparfenyuk/mcp-proxy) and exposes them over HTTPS with bearer token authentication, so any SSE-capable client (Claude Desktop, sandbox environments, coworking machines, etc.) can connect without needing local installations.

## Quick start

1. Copy `.env.example` to `.env` and fill in the values:

   ```bash
   cp .env.example .env
   ```

   | Variable | Description |
   |----------|-------------|
   | `DOMAIN` | Hostname pointed at this server (e.g. `mcp.example.com`) |
   | `BEARER_TOKEN` | Shared secret for client auth (generate: `openssl rand -hex 32`) |
   | `TRACKING_API_TOKEN` | API key from [17track.net](https://www.17track.net/) |

2. Start the stack:

   ```bash
   docker compose up -d --build
   ```

3. Verify health:

   ```bash
   curl https://$DOMAIN/status
   ```

## Endpoints

| Path | Transport | Auth |
|------|-----------|------|
| `/servers/parcel/sse` | SSE | Bearer token |
| `/servers/parcel/mcp` | Streamable HTTP | Bearer token |
| `/status` | HTTP | None |

## Client configuration

Connect any SSE-capable MCP client to:

```
URL: https://mcp.example.com/servers/parcel/sse
Header: Authorization: Bearer <your-token>
```

## Adding a new MCP server

1. Add an entry to `servers.json`:
   ```json
   {
     "mcpServers": {
       "parcel": { "command": "parcel-tracking-mcp-server", "args": [] },
       "new-server": { "command": "new-mcp-server", "args": ["--flag"] }
     }
   }
   ```

2. If it needs a runtime not already in the Dockerfile, add it.

3. If it reads config from `__dirname` (like parcel-tracking-mcp), add config
   generation logic to `entrypoint.sh` and a new env var to `.env`.

4. Rebuild: `docker compose up -d --build`

## config.json path issue

`parcel-tracking-mcp-server` reads config from `path.join(__dirname, "config.json")`,
meaning the file must live next to `index.mjs` inside the npm global install directory
— **not** in the working directory. The `entrypoint.sh` handles this automatically by
writing `config.json` to `$(npm root -g)/parcel-tracking-mcp-server/` at container
startup. If you add another MCP server with a similar pattern, follow the same approach
in the entrypoint.
