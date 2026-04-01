# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Docker Compose setup that exposes stdio-only MCP servers as authenticated SSE/Streamable HTTP endpoints from a VPS. Uses mcp-proxy (Python) to bridge stdio→SSE, fronted by Traefik for TLS and bearer token authentication.

## Commands

```bash
# Build and start
docker compose up -d --build

# View logs
docker compose logs -f mcp-proxy

# Restart after config change
docker compose up -d --build

# Test health
curl https://$DOMAIN/status

# Test with auth
curl -H "Authorization: Bearer $BEARER_TOKEN" https://$DOMAIN/servers/parcel/sse
```

## Key Files

- `docker-compose.yml` — Traefik + mcp-proxy services, all Traefik config via labels
- `Dockerfile` — extends mcp-proxy with Node.js, installs MCP server packages globally
- `entrypoint.sh` — generates config files from env vars, starts mcp-proxy
- `servers.json` — named server definitions for mcp-proxy
- `.env` — secrets and domain config (never committed)

## Adding a New MCP Server

1. Add entry to `servers.json`
2. Install its runtime/package in `Dockerfile` (if needed)
3. Add config generation to `entrypoint.sh` (if it needs config files)
4. Add env vars to `.env` and `.env.example`
5. `docker compose up -d --build`

## config.json Path Gotcha

`parcel-tracking-mcp-server` reads `config.json` from `__dirname` (next to `index.mjs`),
not from the working directory. The entrypoint writes it to `$(npm root -g)/parcel-tracking-mcp-server/`.
Any MCP server with similar behavior needs the same treatment in `entrypoint.sh`.
