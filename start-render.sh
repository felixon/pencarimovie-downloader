#!/usr/bin/env bash
set -e

ROOT_DIR="/app"
FRANKENPHP_BIN="$ROOT_DIR/bin/frankenphp"

HOST="0.0.0.0"
PORT="${PORT:-10000}"
BACKEND="$ROOT_DIR/backend.php"

# Automatically initialize the private Telegram bot session on the
# first Nuvio stream request using the Render environment secret.
if [ -f "$BACKEND" ] && ! grep -q "hosted auto bot login" "$BACKEND"; then
  "$FRANKENPHP_BIN" php -r '
    $file = $argv[1];
    $s = file_get_contents($file);

    $needle = "        // If no bot is connected / bot is disconnected, return instructional connect stream card\n";

    $insert = <<<'PHPBLOCK'
        // On hosted deployments, initialize the private bot session automatically
        // from the server-side environment secret on the first Nuvio stream request.
        if (!$hasSession || $botIdStr === '') {
            $serverBotToken = trim((string) getenv('PENCARIMOVIE_BOT_TOKEN'));

            if ($serverBotToken !== '') {
                [$bootedMadeline, $bootError] = fd_boot_madeline($serverBotToken);

                if ($bootedMadeline) {
                    $botIdStr = fd_get_bot_id();
                    $hasSession = $botIdStr !== '' &&
                        (is_file(FD_SESSION_PATH) || is_dir(FD_SESSION_PATH));

                    unset($bootedMadeline);
                } else {
                    fd_log('hosted auto bot login failed', [
                        'error' => $bootError
                    ]);
                }
            }
        }

PHPBLOCK;

    if (strpos($s, $needle) !== false) {
        $s = str_replace($needle, $insert . $needle, $s, $count);

        if ($count !== 1) {
            fwrite(STDERR, "Unexpected backend patch count: $count\n");
            exit(1);
        }

        file_put_contents($file, $s, LOCK_EX);
    } else {
        fwrite(STDERR, "Backend patch anchor not found\n");
        exit(1);
    }
  ' "$BACKEND"
fi

echo "======================================"
echo "Starting PencariMovie Downloader"
echo "Host: $HOST"
echo "Port: $PORT"
echo "======================================"

if [ ! -x "$FRANKENPHP_BIN" ]; then
    echo "ERROR: FrankenPHP binary not found."
    exit 1
fi

export PATH="$ROOT_DIR/bin:$PATH"
export PHP_BINDIR="$ROOT_DIR/bin"
export PHPRC="$ROOT_DIR/bin"

exec "$FRANKENPHP_BIN" php-server \
    --listen "$HOST:$PORT" \
    --root "$ROOT_DIR"
