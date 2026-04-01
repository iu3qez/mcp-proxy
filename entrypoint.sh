#!/bin/sh
set -e

# --- parcel-tracking-mcp-server config ---
# The package reads config.json from __dirname (next to index.mjs),
# NOT from the working directory. Package is installed to a fixed path
# in the Dockerfile: $MCP_PACKAGES_DIR/node_modules/parcel-tracking-mcp-server/

PARCEL_PKG_DIR="/opt/mcp-packages/node_modules/parcel-mcp"

if [ -z "$TRACKING_API_TOKEN" ]; then
  echo "ERROR: TRACKING_API_TOKEN is not set" >&2
  exit 1
fi

if [ ! -d "$PARCEL_PKG_DIR" ]; then
  echo "ERROR: parcel-tracking-mcp-server not found at $PARCEL_PKG_DIR" >&2
  echo "       Was it installed in the Dockerfile?" >&2
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
