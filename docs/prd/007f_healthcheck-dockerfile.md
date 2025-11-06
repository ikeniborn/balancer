# 6.6 Healthcheck Dockerfile

# /opt/balancer/healthcheck/Dockerfile

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
```

```bash
# /opt/balancer/healthcheck/entrypoint.sh

#!/bin/bash

CHECK_INTERVAL=${CHECK_INTERVAL:-300}

echo "Health Monitor started (interval: ${CHECK_INTERVAL}s)"
echo "Telegram notifications: $([ -n "$TELEGRAM_BOT_TOKEN" ] && echo "enabled" || echo "disabled")"

while true; do
    bash /scripts/health-check.sh
    sleep $CHECK_INTERVAL
done
```

---

[◀ Назад к оглавлению](INDEX.md) | [Следующий раздел ▶](008_deployment.md)
