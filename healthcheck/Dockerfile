FROM alpine:3.18

# Установка зависимостей
RUN apk add --no-cache \
    bash \
    curl \
    openssl \
    docker-cli \
    tzdata \
    && rm -rf /var/cache/apk/*

# Копирование скриптов
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /

ENTRYPOINT ["/entrypoint.sh"]
