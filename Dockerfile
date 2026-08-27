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

COPY app.js /app/app.js
COPY start-render.sh /app/start-render.sh

RUN chmod +x /app/start-render.sh

ENV PENCARIMOVIE_STORAGE_DIR=/app/storage

EXPOSE 10000

CMD ["/app/start-render.sh"]
