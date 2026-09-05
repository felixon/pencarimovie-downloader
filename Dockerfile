FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates tar python3 \
    && rm -rf /var/lib/apt/lists/*

# Use the same PencariMovie v1.1.0 Linux runtime as the known-working
# downloader-server deployment. The v1.0.0 runtime can fail to start the
# MadelineProto stream session under FrankenPHP even when the backend forces
# in-process mode.
RUN curl -fL \
    "https://github.com/aiskendi/pencarimovie-server/releases/download/v1.1.0/pencarimovie-downloader-linux-x86_64.tar.gz" \
    -o /tmp/pencarimovie.tar.gz \
    && tar -xzf /tmp/pencarimovie.tar.gz -C /app \
    && rm /tmp/pencarimovie.tar.gz \
    && chmod +x /app/bin/frankenphp

# Replace the packaged backend with the known-working stream-session
# architecture. It forces MadelineProto in-process and uses the dedicated
# stream-session implementation that works under FrankenPHP.
RUN curl -fL \
    "https://raw.githubusercontent.com/felixon/pencarimovie-downloader-server/e37097010d55c093432df952788e4e752fc691e4/backend.php" \
    -o /app/backend.php

# Long Telegram-backed streams must not be terminated by PHP's default limit.
RUN if grep -qE '^[;[:space:]]*max_execution_time[[:space:]]*=' /app/bin/php.ini; then \
        sed -Ei 's/^[;[:space:]]*max_execution_time[[:space:]]*=.*/max_execution_time = 0/' /app/bin/php.ini; \
    else \
        printf '\nmax_execution_time = 0\n' >> /app/bin/php.ini; \
    fi

# Render compatibility bootstrap. This runs before backend.php.
COPY render-bootstrap.php /app/render-bootstrap.php
RUN printf '\nauto_prepend_file = /app/render-bootstrap.php\n' >> /app/bin/php.ini

# Keep the Render-only local-request compatibility patch for the API routes.
COPY patch-render-local.py /tmp/patch-render-local.py
RUN python3 /tmp/patch-render-local.py && rm -f /tmp/patch-render-local.py

# Temporary stream-stage diagnostics.
COPY patch-stream-debug.py /tmp/patch-stream-debug.py
RUN python3 /tmp/patch-stream-debug.py && rm -f /tmp/patch-stream-debug.py

# Explicitly force MadelineProto's full in-process mode when the settings API
# exposes the setter. The guard keeps the build compatible across releases.
RUN python3 - <<'PY'
from pathlib import Path
p = Path('/app/backend.php')
s = p.read_text(encoding='utf-8')
needle = "    $settings->getLogger()->setLevel(0);"
insert = needle + "\n    if (method_exists($settings->getIpc(), 'setSlow')) {\n        $settings->getIpc()->setSlow(true);\n    }\n    fd_log('madeline full-mode forced', ['self_restart' => isset($_GET['MadelineSelfRestart'])]);"
if needle in s and 'madeline full-mode forced' not in s:
    s = s.replace(needle, insert, 1)
p.write_text(s, encoding='utf-8')
PY

# Render server-side Telegram bot token override.
RUN sed -i "/\$botToken = trim((string) (\$input\['bot_token'\] ?? ''));/a\        \$configuredBotToken = trim((string) (\$_SERVER['PENCARIMOVIE_BOT_TOKEN'] ?? \$_ENV['PENCARIMOVIE_BOT_TOKEN'] ?? ''));\n        if (\$configuredBotToken !== '') {\n            \$botToken = \$configuredBotToken;\n        }" /app/backend.php

# Preserve the existing custom frontend.
COPY app.js /app/public/app.js
COPY patch-app.py /tmp/patch-app.py
COPY patch-performance.py /tmp/patch-performance.py
COPY start-render.sh /app/start-render.sh

RUN python3 /tmp/patch-app.py \
    && python3 /tmp/patch-performance.py \
    && rm -f /tmp/patch-app.py /tmp/patch-performance.py

RUN chmod +x /app/start-render.sh

ENV PENCARIMOVIE_STORAGE_DIR=/app/storage
ENV PENCARIMOVIE_RENDER_MODE=1
ENV PENCARIMOVIE_PUBLIC_HOST=pencarimovie-downloader.onrender.com

EXPOSE 10000

CMD ["/app/start-render.sh"]
