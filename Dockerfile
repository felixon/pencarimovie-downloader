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

# Keep the backend source explicit instead of relying on the copy bundled
# inside the binary release. This lets us patch the streaming endpoint safely
# from this repository while keeping the packaged FrankenPHP/runtime.
RUN curl -fsSL \
    "https://raw.githubusercontent.com/aiskendi/pencarimovie-downloader/main/backend.php" \
    -o /app/backend.php

# The release contains the real frontend under /app/public.
# Replace it with the corrected app.js committed to this repository.
COPY app.js /app/public/app.js
COPY start-render.sh /app/start-render.sh

RUN chmod +x /app/start-render.sh

ENV PENCARIMOVIE_STORAGE_DIR=/app/storage

EXPOSE 10000

CMD ["/app/start-render.sh"]
