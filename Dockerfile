FROM ghcr.io/sparfenyuk/mcp-proxy:latest

# Install Node.js (needed for node-based MCP servers)
RUN apk add --no-cache nodejs npm

# Pre-install parcel-tracking-mcp-server globally for predictable path
# entrypoint.sh writes config.json to $(npm root -g)/parcel-tracking-mcp-server/
RUN npm install -g parcel-tracking-mcp-server

COPY servers.json /app/servers.json
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
