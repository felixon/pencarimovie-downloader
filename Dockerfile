FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates tar python3 \
    && rm -rf /var/lib/apt/lists/*

# Use the developer's v1.1.0 runtime, while keeping this repository's
# existing Render/frontend customizations below.
RUN curl -fL \
    "https://github.com/aiskendi/pencarimovie-downloader/releases/download/v1.1.0/pencarimovie-downloader-linux-x86_64.tar.gz" \
    -o /tmp/pencarimovie.tar.gz \
    && tar -xzf /tmp/pencarimovie.tar.gz -C /app \
    && rm /tmp/pencarimovie.tar.gz \
    && chmod +x /app/bin/frankenphp

# iPhone/Safari can take longer than PHP's default 30-second execution limit
# while the Telegram-backed video stream is being established or read.
RUN if grep -qE '^[;[:space:]]*max_execution_time[[:space:]]*=' /app/bin/php.ini; then \
        sed -Ei 's/^[;[:space:]]*max_execution_time[[:space:]]*=.*/max_execution_time = 0/' /app/bin/php.ini; \
    else \
        printf '\nmax_execution_time = 0\n' >> /app/bin/php.ini; \
    fi

# Apply only the Render compatibility changes needed for the v1.1.0 backend.
# The upstream local-only security check remains intact for normal deployments;
# this explicit flag only disables its Cloudflare-header classification on this
# trusted server deployment so Render proxy traffic can use the dashboard API.
COPY patch-render-v1.1.py /tmp/patch-render-v1.1.py
RUN python3 /tmp/patch-render-v1.1.py \
    && rm -f /tmp/patch-render-v1.1.py

# The release's bot login remains intact, but Render can supply the configured
# bot token through the existing PENCARIMOVIE_BOT_TOKEN environment variable.
# The v1.1 patch above injects this override without changing the frontend flow.

# Preserve the existing custom frontend and performance work.
COPY app.js /app/public/app.js
COPY patch-app.py /tmp/patch-app.py
COPY patch-performance.py /tmp/patch-performance.py
COPY start-render.sh /app/start-render.sh

# Performance patches: don't block first paint and don't create a large burst
# of category API calls on small Render instances.
RUN python3 /tmp/patch-app.py \
    && python3 /tmp/patch-performance.py \
    && rm -f /tmp/patch-app.py /tmp/patch-performance.py

RUN chmod +x /app/start-render.sh

ENV PENCARIMOVIE_STORAGE_DIR=/app/storage
ENV PENCARIMOVIE_RENDER_MODE=1

EXPOSE 10000

CMD ["/app/start-render.sh"]
