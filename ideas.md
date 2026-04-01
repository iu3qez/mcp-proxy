Multi-server con un singolo proxy
Con mcp-proxy (Python) puoi usare --named-server per servire più server stdio su path separati /servers/<NAME>/ GitHub — un solo container, un solo entry Traefik per tutti i tuoi MCP locali.
bashmcp-proxy --port 8080 \
  --named-server parcel "npx parcel-tracking-mcp-server" \
  --named-server filesystem "npx @modelcontextprotocol/server-filesystem /data"

partiamo con @modelcontextprotocol/sdk in docker compose.

Autenticazione via ScaleKit o bearer token
