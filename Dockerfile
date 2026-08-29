FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates tar \
    && rm -rf /var/lib/apt/lists/*

RUN curl -L \
    "https://github.com/aiskendi/pencarimovie-downloader/releases/download/v1.0.0/pencarimovie-downloader-linux-x86_64.tar.gz" \
    -o /tmp/pencarimovie.tar.gz \
    && tar -xzf /tmp/pencarimovie.tar.gz -C /app \
    && rm /tmp/pencarimovie.tar.gz \
    && chmod +x /app/bin/frankenphp

# iPhone/Safari can take longer than PHP's default 30-second execution limit
# while the Telegram-backed video stream is being established or read.
# Keep the packaged runtime/backend unchanged, but disable only PHP's script
# execution timeout so long video streams are not terminated at 30 seconds.
RUN if grep -qE '^[;[:space:]]*max_execution_time[[:space:]]*=' /app/bin/php.ini; then \
        sed -Ei 's/^[;[:space:]]*max_execution_time[[:space:]]*=.*/max_execution_time = 0/' /app/bin/php.ini; \
    else \
        printf '\nmax_execution_time = 0\n' >> /app/bin/php.ini; \
    fi

# Render can provide a fixed Telegram bot token through the
# PENCARIMOVIE_BOT_TOKEN environment variable. The upstream backend normally
# uses the token submitted by the browser and asks WordPress to validate it.
# On a hosted deployment we want the server-side token to be authoritative,
# so patch the upstream bot-login handler to use the Render environment token
# when it is present. The token is never written into the image or frontend.
RUN sed -i "/\$botToken = trim((string) (\$input\['bot_token'\] ?? ''));/a\        \$configuredBotToken = trim((string) (\$_SERVER['PENCARIMOVIE_BOT_TOKEN'] ?? \$_ENV['PENCARIMOVIE_BOT_TOKEN'] ?? ''));\n        if (\$configuredBotToken !== '') {\n            \$botToken = \$configuredBotToken;\n        }" /app/backend.php

# The release contains the real frontend under /app/public.
# Replace it with the corrected app.js committed to this repository.
COPY app.js /app/public/app.js
COPY start-render.sh /app/start-render.sh

RUN chmod +x /app/start-render.sh

ENV PENCARIMOVIE_STORAGE_DIR=/app/storage

EXPOSE 10000

CMD ["/app/start-render.sh"]
