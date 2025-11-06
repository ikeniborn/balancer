# 5.3 Snippets (переиспользуемые блоки)

# TCP/UDP Stream проксирование
stream {
    log_format stream_detailed '$remote_addr [$time_local] '
                               '$protocol $status $bytes_sent $bytes_received '
                               '$session_time "$upstream_addr" '
                               '"$upstream_bytes_sent" "$upstream_bytes_received" '
                               '"$upstream_connect_time"';

    access_log /var/log/nginx/stream-access.log stream_detailed;
    error_log /var/log/nginx/stream-error.log warn;

    # Загрузка TCP/UDP конфигураций
    include /etc/nginx/conf.d/streams.conf;
}
```

#### 5.3.1 SSL параметры

```nginx
# /opt/balancer/nginx/snippets/ssl-params.conf

# Современные SSL/TLS настройки
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';

# Эллиптические кривые
ssl_ecdh_curve secp384r1:X25519:prime256v1;

# Сессии SSL
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:50m;
ssl_session_tickets off;

# OCSP Stapling
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 1.1.1.1 valid=300s;
resolver_timeout 5s;

# Размер буфера SSL
ssl_buffer_size 4k;

# HSTS (раскомментировать после тестирования)
# add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
```

#### 5.3.2 Заголовки безопасности

```nginx
# /opt/balancer/nginx/snippets/security-headers.conf

# Защита от clickjacking
add_header X-Frame-Options "SAMEORIGIN" always;

# Предотвращение MIME-type sniffing
add_header X-Content-Type-Options "nosniff" always;

# XSS Protection (legacy, но оставляем для совместимости)
add_header X-XSS-Protection "1; mode=block" always;

# Referrer Policy
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

# Content Security Policy (настроить под проект)
add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'" always;

# Permissions Policy
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

# X-Permitted-Cross-Domain-Policies
add_header X-Permitted-Cross-Domain-Policies "none" always;
```

#### 5.3.3 Proxy параметры

```nginx
# /opt/balancer/nginx/snippets/proxy-params.conf

# Передача информации о клиенте
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $server_name;
proxy_set_header X-Forwarded-Port $server_port;

# Таймауты
proxy_connect_timeout 60s;
proxy_send_timeout 60s;
proxy_read_timeout 60s;

# Буферизация
proxy_buffering on;
proxy_buffer_size 8k;
proxy_buffers 16 8k;
proxy_busy_buffers_size 16k;
proxy_temp_file_write_size 16k;

# HTTP версия для upstream
proxy_http_version 1.1;

# WebSocket поддержка
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $connection_upgrade;

# Отключение перенаправления от backend
proxy_redirect off;
```

#### 5.3.4 Параметры кеширования

```nginx

---

[◀ Назад к оглавлению](INDEX.md) | [Следующий раздел ▶](006d_service-templates.md)
