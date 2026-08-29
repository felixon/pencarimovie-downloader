FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates tar \
    && rm -rf /var/lib/apt/lists/*

# Get the official PencariMovie runtime. The package contains FrankenPHP,
# PHP extensions, Composer dependencies, and the public frontend assets.
RUN curl -L \
    "https://github.com/aiskendi/pencarimovie-downloader/releases/download/v1.0.0/pencarimovie-downloader-linux-x86_64.tar.gz" \
    -o /tmp/pencarimovie.tar.gz \
    && tar -xzf /tmp/pencarimovie.tar.gz -C /app \
    && rm /tmp/pencarimovie.tar.gz \
    && chmod +x /app/bin/frankenphp

# IMPORTANT: do not rely on the backend bundled inside the release archive.
# The upstream repository contains the actively maintained backend.php and
# index.php, including the current Nuvio/Telegram streaming implementation.
# Pull those source files at build time so the Render deployment gets the
# current backend while we keep our customized frontend app.js in this fork.
RUN curl -fsSL \
    "https://raw.githubusercontent.com/aiskendi/pencarimovie-downloader/main/backend.php" \
    -o /app/backend.php \
    && curl -fsSL \
    "https://raw.githubusercontent.com/aiskendi/pencarimovie-downloader/main/index.php" \
    -o /app/index.php

# iPhone/Safari can take longer than PHP's default execution limit while
# establishing/reading a Telegram-backed video stream. Disable the PHP
# execution timeout specifically for the downloadToBrowser() streaming call.
# Keep the existing Android/Nuvio streaming implementation unchanged.
RUN sed -i '/\$madeline->downloadToBrowser/i\    @set_time_limit(0);\
    @ini_set("max_execution_time", "0");' /app/backend.php

# Replace the upstream frontend with the customized version committed here.
COPY app.js /app/public/app.js
COPY start-render.sh /app/start-render.sh

RUN chmod +x /app/start-render.sh

ENV PENCARIMOVIE_STORAGE_DIR=/app/storage

EXPOSE 10000

CMD ["/app/start-render.sh"]
