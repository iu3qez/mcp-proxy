# MCP Proxy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Docker Compose setup that exposes stdio MCP servers as authenticated SSE endpoints from a VPS, starting with parcel-tracking-mcp.

**Architecture:** Single mcp-proxy container (with Node.js added) spawns stdio MCP servers as child processes and exposes them via SSE/Streamable HTTP. Traefik handles TLS and bearer token auth via `traefik-plugin-apikey`.

**Tech Stack:** Docker Compose, Traefik v3, mcp-proxy (Python), Node.js, traefik-plugin-apikey

---

## Critical Implementation Detail: config.json Path

`parcel-tracking-mcp-server` reads its config from `path.join(__dirname, "config.json")` — meaning the `config.json` file **must** live in the same directory as the package's `index.mjs`, NOT in the working directory.

With `npm install -g parcel-tracking-mcp-server`, the package lands in a predictable path:
```
/usr/local/lib/node_modules/parcel-tracking-mcp-server/
├── index.mjs        ← __dirname points here
├── carriers.csv
└── config.json      ← must be written here by entrypoint.sh
```

The `entrypoint.sh` must:
1. Determine the global install path: `$(npm root -g)/parcel-tracking-mcp-server/`
2. Write `config.json` with the API token into that directory
3. Only then start mcp-proxy

If the package structure changes in a future version, the entrypoint will fail loudly (config.json write to nonexistent path), which is the correct behavior — it surfaces the problem immediately.

---

### Task 1: Project Scaffolding

**Files:**
- Create: `.gitignore`
- Create: `.env.example`
- Create: `README.md`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
.env
traefik/acme.json
```

- [ ] **Step 2: Create `.env.example`**

```env
# Hostname for Traefik TLS certificate and routing
DOMAIN=mcp.example.com

# Bearer token for API authentication (generate with: openssl rand -hex 32)
BEARER_TOKEN=

# 17track.net API key for parcel-tracking-mcp
TRACKING_API_TOKEN=
```

- [ ] **Step 3: Create `README.md`**

```markdown
# MCP Proxy

Docker Compose setup that exposes stdio-only MCP servers as authenticated SSE endpoints.

## What it does

Many MCP servers only support stdio transport. This project wraps them with
[mcp-proxy](https://github.com/sparfenyuk/mcp-proxy) and exposes them over
HTTPS with bearer token authentication, so remote SSE clients (Claude Desktop,
sandbox environments, etc.) can use them.

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
```

- [ ] **Step 4: Commit**

```bash
git init
git add .gitignore .env.example README.md
git commit -m "chore: project scaffolding with gitignore, env template, and readme"
```

---

### Task 2: Dockerfile

**Files:**
- Create: `Dockerfile`

- [ ] **Step 1: Create `Dockerfile`**

```dockerfile
FROM ghcr.io/sparfenyuk/mcp-proxy:latest

# Install Node.js (needed for npx/node-based MCP servers)
RUN apk add --no-cache nodejs npm

# Pre-install parcel-tracking-mcp-server globally for predictable path
RUN npm install -g parcel-tracking-mcp-server

COPY servers.json /app/servers.json
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
```

Note: The base image `ghcr.io/sparfenyuk/mcp-proxy` is Alpine-based, so we use `apk`. If this fails, check the base image OS with `docker run --rm ghcr.io/sparfenyuk/mcp-proxy:latest cat /etc/os-release` and adjust.

- [ ] **Step 2: Commit**

```bash
git add Dockerfile
git commit -m "feat: dockerfile extending mcp-proxy with node.js runtime"
```

---

### Task 3: servers.json and entrypoint.sh

**Files:**
- Create: `servers.json`
- Create: `entrypoint.sh`

- [ ] **Step 1: Create `servers.json`**

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

- [ ] **Step 2: Create `entrypoint.sh`**

This is the critical file that bridges `.env` values to the MCP server config.

```bash
#!/bin/sh
set -e

# --- parcel-tracking-mcp-server config ---
# The package reads config.json from __dirname (next to index.mjs),
# NOT from the working directory. We must write it to the global
# npm install path.

PARCEL_PKG_DIR="$(npm root -g)/parcel-tracking-mcp-server"

if [ -z "$TRACKING_API_TOKEN" ]; then
  echo "ERROR: TRACKING_API_TOKEN is not set" >&2
  exit 1
fi

if [ ! -d "$PARCEL_PKG_DIR" ]; then
  echo "ERROR: parcel-tracking-mcp-server not found at $PARCEL_PKG_DIR" >&2
  echo "       Was it installed globally in the Dockerfile?" >&2
  exit 1
fi

cat > "$PARCEL_PKG_DIR/config.json" <<EOF
{
  "apiToken": "$TRACKING_API_TOKEN"
}
EOF

echo "Wrote config.json to $PARCEL_PKG_DIR/config.json"

# --- Start mcp-proxy ---
exec mcp-proxy --host 0.0.0.0 --port 8080 --named-server-config /app/servers.json
```

- [ ] **Step 3: Test entrypoint locally (optional, manual)**

```bash
docker build -t mcp-proxy-test .
docker run --rm -e TRACKING_API_TOKEN=test-token mcp-proxy-test sh -c '
  PARCEL_PKG_DIR="$(npm root -g)/parcel-tracking-mcp-server"
  echo "Package dir: $PARCEL_PKG_DIR"
  ls -la "$PARCEL_PKG_DIR/"
'
```

Expected: lists `index.mjs`, `carriers.csv`, and other package files. This confirms the global install path is correct.

- [ ] **Step 4: Commit**

```bash
git add servers.json entrypoint.sh
git commit -m "feat: entrypoint with config.json injection and named server config"
```

---

### Task 4: Docker Compose with Traefik

**Files:**
- Create: `docker-compose.yml`

- [ ] **Step 1: Create `docker-compose.yml`**

```yaml
services:
  traefik:
    image: traefik:v3.4
    restart: unless-stopped
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      # HTTP -> HTTPS redirect
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      # Let's Encrypt
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.storage=/acme.json"
      # Plugin: traefik-plugin-apikey
      - "--experimental.plugins.apikey.modulename=github.com/Gerardwx/traefik-plugin-apikey"
      - "--experimental.plugins.apikey.version=v0.2.1"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/acme.json:/acme.json
    networks:
      - proxy

  mcp-proxy:
    build: .
    restart: unless-stopped
    environment:
      - TRACKING_API_TOKEN=${TRACKING_API_TOKEN}
    labels:
      - "traefik.enable=true"
      # Router
      - "traefik.http.routers.mcp.rule=Host(`${DOMAIN}`)"
      - "traefik.http.routers.mcp.entrypoints=websecure"
      - "traefik.http.routers.mcp.tls.certresolver=letsencrypt"
      - "traefik.http.routers.mcp.middlewares=mcp-auth"
      # Service
      - "traefik.http.services.mcp.loadbalancer.server.port=8080"
      # Middleware: bearer token auth via traefik-plugin-apikey
      - "traefik.http.middlewares.mcp-auth.plugin.apikey.keySource=header"
      - "traefik.http.middlewares.mcp-auth.plugin.apikey.headerName=Authorization"
      - "traefik.http.middlewares.mcp-auth.plugin.apikey.headerValuePrefix=Bearer "
      - "traefik.http.middlewares.mcp-auth.plugin.apikey.keys=${BEARER_TOKEN}"
      # Health check router (no auth)
      - "traefik.http.routers.mcp-health.rule=Host(`${DOMAIN}`) && Path(`/status`)"
      - "traefik.http.routers.mcp-health.entrypoints=websecure"
      - "traefik.http.routers.mcp-health.tls.certresolver=letsencrypt"
      - "traefik.http.routers.mcp-health.priority=100"
    networks:
      - proxy

networks:
  proxy:
    driver: bridge
```

Note on `traefik-plugin-apikey` config: the plugin extracts the token from the `Authorization` header after stripping the `Bearer ` prefix, then matches against the `keys` list. Check the [plugin README](https://github.com/Gerardwx/traefik-plugin-apikey) if the label syntax has changed.

- [ ] **Step 2: Create acme.json placeholder**

```bash
mkdir -p traefik
touch traefik/acme.json
chmod 600 traefik/acme.json
```

- [ ] **Step 3: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: docker compose with traefik, tls, and bearer token auth"
```

---

### Task 5: End-to-End Verification

- [ ] **Step 1: Create `.env` from template**

```bash
cp .env.example .env
# Edit .env with real values:
# - DOMAIN: your actual domain
# - BEARER_TOKEN: generate with `openssl rand -hex 32`
# - TRACKING_API_TOKEN: your 17track API key
```

- [ ] **Step 2: Build and start**

```bash
docker compose up -d --build
```

- [ ] **Step 3: Check container health**

```bash
docker compose ps
docker compose logs mcp-proxy
```

Expected: mcp-proxy container running, logs show "Wrote config.json to ..." and mcp-proxy startup message.

- [ ] **Step 4: Test health endpoint (no auth)**

```bash
curl https://$DOMAIN/status
```

Expected: 200 OK response.

- [ ] **Step 5: Test SSE endpoint without token (should fail)**

```bash
curl -i https://$DOMAIN/servers/parcel/sse
```

Expected: 401 or 403 response from traefik-plugin-apikey.

- [ ] **Step 6: Test SSE endpoint with token**

```bash
curl -i -H "Authorization: Bearer $BEARER_TOKEN" https://$DOMAIN/servers/parcel/sse
```

Expected: 200 with `Content-Type: text/event-stream`, SSE connection established.

- [ ] **Step 7: Commit any fixes**

If any adjustments were needed during testing, commit them:

```bash
git add -A
git commit -m "fix: adjustments from e2e verification"
```

---

### Task 6: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md with actual build/run commands**

Replace the current CLAUDE.md content with up-to-date information now that the project is implemented:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with actual commands and architecture"
```
