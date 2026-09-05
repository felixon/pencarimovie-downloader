#!/usr/bin/env bash
set -e

ROOT_DIR="/app"
FRANKENPHP_BIN="$ROOT_DIR/bin/frankenphp"
HOST="0.0.0.0"
PORT="${PORT:-10000}"

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

# Keep startup single-process and deterministic. Do not call /api/botlogin
# concurrently from a background warmup: MadelineProto must exclusively own
# the session while login is initializing, otherwise the user request can
# contend for the same session lock and hit the 30-second serialization timeout.
exec "$FRANKENPHP_BIN" php-server \
    --listen "$HOST:$PORT" \
    --root "$ROOT_DIR"
