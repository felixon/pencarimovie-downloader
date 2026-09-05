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

# Start the web server first so Render can see the listening port immediately.
"$FRANKENPHP_BIN" php-server \
    --listen "$HOST:$PORT" \
    --root "$ROOT_DIR" &
SERVER_PID=$!

# Warm the authenticated bot/MadelineProto path in the background. The backend
# has a server-side bot-token override, so the warmup request does not need to
# put the secret into the HTTP request. This lets stream-session preparation
# happen before the first real /api/download request.
if [ -n "${PENCARIMOVIE_BOT_TOKEN:-}" ]; then
    (
        for i in $(seq 1 30); do
            if curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done

        echo "[Render warmup] Starting bot/MadelineProto warmup"
        if curl -sS --max-time 120 \
            -X POST \
            -H 'Content-Type: application/json' \
            -H 'Accept: application/json' \
            --data '{}' \
            "http://127.0.0.1:${PORT}/api/botlogin" \
            >/tmp/pencarimovie-warmup.json 2>/dev/null; then
            echo "[Render warmup] botlogin warmup request completed"
        else
            echo "[Render warmup] botlogin warmup request failed or timed out"
        fi
        rm -f /tmp/pencarimovie-warmup.json
    ) &
fi

# Keep the main server process attached to the container.
wait "$SERVER_PID"
