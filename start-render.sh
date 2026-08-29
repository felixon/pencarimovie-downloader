#!/usr/bin/env bash
set -e

ROOT_DIR="/app"
FRANKENPHP_BIN="$ROOT_DIR/bin/frankenphp"
HOST="0.0.0.0"
PORT="${PORT:-10000}"

# Render/FrankenPHP startup must stay simple. The backend.php and index.php
# used by this deployment are downloaded by the Dockerfile from the upstream
# PencariMovie release source. Do not rewrite or patch backend.php at runtime:
# doing so makes deployment depend on exact source-code anchors and can prevent
# the web server from starting.

echo "======================================"
echo "Starting PencariMovie Downloader"
echo "Host: $HOST"
echo "Port: $PORT"
echo "======================================"

if [ ! -x "$FRANKENPHP_BIN" ]; then
    echo "ERROR: FrankenPHP binary not found at $FRANKENPHP_BIN"
    exit 1
fi

export PATH="$ROOT_DIR/bin:$PATH"
export PHP_BINDIR="$ROOT_DIR/bin"
export PHPRC="$ROOT_DIR/bin"

# FrankenPHP's embedded PHP CLI is exposed as php-server. Render supplies the
# public PORT through the PORT environment variable.
exec "$FRANKENPHP_BIN" php-server \
    --listen "$HOST:$PORT" \
    --root "$ROOT_DIR"
