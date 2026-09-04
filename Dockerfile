FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates tar python3 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -L \
    "https://github.com/aiskendi/pencarimovie-downloader/releases/download/v1.0.0/pencarimovie-downloader-linux-x86_64.tar.gz" \
    -o /tmp/pencarimovie.tar.gz \
    && tar -xzf /tmp/pencarimovie.tar.gz -C /app \
    && rm /tmp/pencarimovie.tar.gz \
    && chmod +x /app/bin/frankenphp

# Long Telegram-backed streams must not be terminated by PHP's default limit.
RUN if grep -qE '^[;[:space:]]*max_execution_time[[:space:]]*=' /app/bin/php.ini; then \
        sed -Ei 's/^[;[:space:]]*max_execution_time[[:space:]]*=.*/max_execution_time = 0/' /app/bin/php.ini; \
    else \
        printf '\nmax_execution_time = 0\n' >> /app/bin/php.ini; \
    fi

# Initialize MadelineProto in-process before backend.php loads. This mirrors
# the known-working server architecture and targets stream startup only.
COPY render-bootstrap.php /app/render-bootstrap.php
RUN printf '\nauto_prepend_file = /app/render-bootstrap.php\n' >> /app/bin/php.ini

# Render's reverse proxy means the upstream local-only check can reject a
# legitimate request. Enable the bypass only when this deployment explicitly
# sets PENCARIMOVIE_RENDER_MODE=1.
COPY patch-render-local.py /tmp/patch-render-local.py
RUN python3 /tmp/patch-render-local.py && rm -f /tmp/patch-render-local.py

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

EXPOSE 10000

CMD ["/app/start-render.sh"]
