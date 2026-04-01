FROM oven/bun:alpine AS bun

FROM ghcr.io/sparfenyuk/mcp-proxy:latest

# Install Node.js runtime
RUN apk add --no-cache nodejs

# Copy bun binary from official image (avoids install script issues on Alpine/musl)
COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun

# Install parcel-tracking-mcp-server to a fixed path
# entrypoint.sh writes config.json to /opt/mcp-packages/node_modules/parcel-tracking-mcp-server/
ENV MCP_PACKAGES_DIR=/opt/mcp-packages
RUN mkdir -p $MCP_PACKAGES_DIR && cd $MCP_PACKAGES_DIR && bun add parcel-tracking-mcp-server

COPY servers.json /app/servers.json
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
