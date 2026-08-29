#!/usr/bin/env bash
set -e

ROOT_DIR="/app"
FRANKENPHP_BIN="$ROOT_DIR/bin/frankenphp"

HOST="0.0.0.0"
PORT="${PORT:-10000}"
BACKEND="$ROOT_DIR/backend.php"

# Render needs the Telegram session to be available to Nuvio without
# requiring a user to open the dashboard first. The bot token itself stays
# only in Render Environment Variables; it is never written to this file.
#
# We also patch the browser/Nuvio download route so it can serve Telegram
# media with HTTP byte-range support. This is important for FFmpeg/Safari and
# avoids relying on downloadToBrowser() for a long-lived media response.
if [ -f "$BACKEND" ]; then
    cat > /tmp/patch_pencarimovie.php <<'PHP'
<?php
$file = $argv[1] ?? '';
if ($file === '' || !is_file($file)) {
    fwrite(STDERR, "Backend file not found\n");
    exit(1);
}

$source = file_get_contents($file);
if ($source === false) {
    fwrite(STDERR, "Unable to read backend\n");
    exit(1);
}

function patch_once(string &$source, string $needle, string $insert, string $label): void
{
    if (strpos($source, $insert) !== false) {
        return;
    }

    $count = substr_count($source, $needle);
    if ($count !== 1) {
        fwrite(STDERR, "{$label}: expected one patch anchor, found {$count}\n");
        exit(1);
    }

    $source = str_replace($needle, $insert . $needle, $source, $count);
    if ($count !== 1) {
        fwrite(STDERR, "{$label}: unexpected replacement count\n");
        exit(1);
    }
}

// 1. Hosted Nuvio auto-login.
// The upstream backend normally returns a "Connect Bot" stream card when
// no MadelineProto session exists. On Render, use the server-side bot token
// to create/resume that session automatically.
$streamAnchor = "        // If no bot is connected / bot is disconnected, return instructional connect stream card\n";
$streamInsert = <<<'PHPBLOCK'
        // Hosted Render deployment: automatically initialize the private bot
        // session from the server-side environment secret before Nuvio gets
        // the "Bot not connected" fallback stream.
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
                    fd_log('hosted auto bot login failed', ['error' => $bootError]);
                }
            }
        }

PHPBLOCK;
patch_once($source, $streamAnchor, $streamInsert, 'hosted auto-login');

// 2. Never let PHP's default 30-second execution limit kill a media request.
$downloadAnchor = "    if ($path === '/api/download') {\n";
$downloadGuard = <<<'PHPBLOCK'
    if ($path === '/api/download') {
        // Media requests can legitimately stay open for the duration of a movie.
        @set_time_limit(0);
        @ignore_user_abort(true);
        while (ob_get_level() > 0) {
            @ob_end_clean();
        }

PHPBLOCK;
patch_once($source, $downloadAnchor, $downloadGuard, 'download timeout guard');

// 3. Replace downloadToBrowser() with an explicit HTTP byte-range streamer.
// Nuvio/FFmpeg commonly requests media with Range headers; Safari also relies
// on range requests. downloadToStream() supports byte offsets directly.
$oldDownload = <<<'PHPBLOCK'
        try {
            fd_log('starting downloadToBrowser', [
                'file_id' => $fileId,
                'file_size' => $fileSize,
                'file_name' => $fileName,
                'mime' => $fileMime,
            ]);
            $madeline->downloadToBrowser($fileId, null, $fileSize, $fileName, $fileMime);
        } catch (Throwable $throwable) {
            fd_log('downloadToBrowser failed', [
                'error' => $throwable->getMessage(),
            ]);
            fd_json([
                'ok' => 0,
                'message' => 'File download failed.',
            ], 500);
        }
PHPBLOCK;

$newDownload = <<<'PHPBLOCK'
        try {
            $rangeHeader = trim((string) ($_SERVER['HTTP_RANGE'] ?? ''));
            $start = 0;
            $end = $fileSize - 1;
            $status = 200;

            if ($rangeHeader !== '' && preg_match('/bytes=(\d*)-(\d*)/i', $rangeHeader, $rangeMatch)) {
                $rangeStart = $rangeMatch[1] ?? '';
                $rangeEnd = $rangeMatch[2] ?? '';

                if ($rangeStart === '' && $rangeEnd === '') {
                    header('Content-Range: bytes */' . $fileSize);
                    http_response_code(416);
                    exit;
                }

                if ($rangeStart === '') {
                    $suffixLength = (int) $rangeEnd;
                    if ($suffixLength <= 0) {
                        header('Content-Range: bytes */' . $fileSize);
                        http_response_code(416);
                        exit;
                    }
                    $start = max(0, $fileSize - $suffixLength);
                } else {
                    $start = (int) $rangeStart;
                }

                if ($rangeEnd !== '') {
                    $end = (int) $rangeEnd;
                }

                if ($start < 0 || $start >= $fileSize || $end < $start) {
                    header('Content-Range: bytes */' . $fileSize);
                    http_response_code(416);
                    exit;
                }

                $end = min($end, $fileSize - 1);
                $status = 206;
            }

            $contentLength = $end - $start + 1;
            $safeName = str_replace(["\r", "\n", '"'], '', $fileName);
            $contentType = $fileMime !== '' ? $fileMime : 'application/octet-stream';

            header('Content-Type: ' . $contentType);
            header('Content-Disposition: inline; filename="' . $safeName . '"');
            header('Accept-Ranges: bytes');
            header('Cache-Control: no-store, no-cache, must-revalidate');
            header('Pragma: no-cache');
            header('Content-Length: ' . $contentLength);
            if ($status === 206) {
                header('Content-Range: bytes ' . $start . '-' . $end . '/' . $fileSize);
            }
            http_response_code($status);

            fd_log('starting range stream', [
                'file_id' => $fileId,
                'start' => $start,
                'end' => $end,
                'length' => $contentLength,
                'status' => $status,
                'range_header' => $rangeHeader,
            ]);

            $output = fopen('php://output', 'wb');
            if ($output === false) {
                throw new RuntimeException('Unable to open output stream.');
            }

            $madeline->downloadToStream($fileId, $output, null, $start, $end + 1);
            fclose($output);
        } catch (Throwable $throwable) {
            fd_log('range stream failed', [
                'error' => $throwable->getMessage(),
            ]);

            // Headers may already have been sent once media streaming starts.
            // Only return JSON when it is still safe to do so.
            if (!headers_sent()) {
                fd_json([
                    'ok' => 0,
                    'message' => 'File download failed.',
                ], 500);
            }
        }
PHPBLOCK;

if (strpos($source, $newDownload) === false) {
    $count = substr_count($source, $oldDownload);
    if ($count !== 1) {
        fwrite(STDERR, "range stream: expected one download block, found {$count}\n");
        exit(1);
    }
    $source = str_replace($oldDownload, $newDownload, $source, $count);
    if ($count !== 1) {
        fwrite(STDERR, "range stream: unexpected replacement count\n");
        exit(1);
    }
}

if (file_put_contents($file, $source, LOCK_EX) === false) {
    fwrite(STDERR, "Unable to write patched backend\n");
    exit(1);
}

echo "PencariMovie Render backend patches applied\n";
PHP

    "$FRANKENPHP_BIN" php /tmp/patch_pencarimovie.php "$BACKEND"
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
