# 4. Конфигурации для Direct Static Mount

## 4. Конфигурации для direct mount

### 4.1 Snippet для статики

```nginx
# /opt/balancer/nginx/snippets/static-params.conf

# Оптимизация для статического контента
sendfile on;
sendfile_max_chunk 1m;
tcp_nopush on;

# Кеширование на стороне клиента
expires 1y;
add_header Cache-Control "public, immutable";

# Проверка свежести контента
if_modified_since before;

# Отключение логирования для статики
access_log off;

# Компрессия
gzip_static on;

# Open file cache
open_file_cache max=1000 inactive=20s;
open_file_cache_valid 30s;
open_file_cache_min_uses 2;
open_file_cache_errors off;
```

### 4.2 Шаблон для Direct Static Frontend

```nginx
# /opt/balancer/templates/service-frontend-static.conf.tmpl

# Upstream не нужен - обслуживается напрямую
map $sent_http_content_type $expires {
    default                    off;
    text/html                  epoch;
    text/css                   max;
    application/javascript     max;
    application/json           epoch;
    ~image/                    max;
    ~font/                     max;
}

# HTTP -> HTTPS редирект
server {
    listen 80;
    listen [::]:80;
    server_name {DOMAIN};

    # Let's Encrypt ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        allow all;
    }

    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS сервер для статики
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name {DOMAIN};

    # SSL сертификаты
    ssl_certificate /etc/letsencrypt/live/{DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{DOMAIN}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/{DOMAIN}/chain.pem;

    # Подключение общих параметров
    include /etc/nginx/snippets/ssl-params.conf;
    include /etc/nginx/snippets/security-headers.conf;

    # Логи
    access_log /var/log/nginx/static-{SERVICE_NAME}-access.log detailed;
    error_log /var/log/nginx/static-{SERVICE_NAME}-error.log warn;

    # Rate limiting
    limit_req zone=general burst=50 nodelay;

    # Корневая директория статики
    root /usr/share/nginx/static/{SERVICE_NAME};
    index index.html;

    # Charset
    charset utf-8;

    # Основная локация для SPA
    location / {
        # Попробовать файл, затем директорию, затем fallback на index.html
        try_files $uri $uri/ /index.html;
        
        # Кеширование HTML
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        expires -1;
    }

    # Статические ассеты с агрессивным кешированием
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|otf)$ {
        include /etc/nginx/snippets/static-params.conf;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # JSON файлы (могут обновляться)
    location ~* \.json$ {
        add_header Cache-Control "no-cache";
        expires -1;
    }

    # Manifest и service worker
    location ~* \.(manifest|webmanifest)$ {
        add_header Cache-Control "public, max-age=3600";
        expires 1h;
    }

    location = /service-worker.js {
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        expires -1;
    }

    # Отключить доступ к dot-файлам
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Отключить доступ к исходникам (опционально)
    location ~* \.(map|ts|tsx|jsx)$ {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Gzip для текстовых файлов
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/rss+xml
        image/svg+xml;

    # Версия приложения (для мониторинга)
    location /.version {
        default_type text/plain;
        expires -1;
        add_header Cache-Control "no-cache";
    }

    # Health check
    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }
}
```

### 4.3 Сравнительный шаблон Proxy Frontend

```nginx
# /opt/balancer/templates/service-frontend-proxy.conf.tmpl
# Для случаев когда frontend в отдельном контейнере

# Upstream для frontend контейнера
upstream {SERVICE_NAME}_frontend {
    server {BACKEND_HOST}:{BACKEND_PORT} max_fails=3 fail_timeout=30s;
    keepalive 32;
}

# HTTP -> HTTPS редирект
server {
    listen 80;
    listen [::]:80;
    server_name {DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        allow all;
    }

    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS сервер для проксирования
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name {DOMAIN};

    ssl_certificate /etc/letsencrypt/live/{DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{DOMAIN}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/{DOMAIN}/chain.pem;

    include /etc/nginx/snippets/ssl-params.conf;
    include /etc/nginx/snippets/security-headers.conf;

    access_log /var/log/nginx/external-{SERVICE_NAME}-access.log detailed;
    error_log /var/log/nginx/external-{SERVICE_NAME}-error.log warn;

    limit_req zone=general burst=50 nodelay;

    location / {
        include /etc/nginx/snippets/proxy-params.conf;
        proxy_pass http://{SERVICE_NAME}_frontend;
    }

    # Кеширование статики от upstream
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot|otf)$ {
        proxy_cache STATIC;
        proxy_cache_valid 200 7d;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        
        add_header X-Cache-Status $upstream_cache_status;
        expires 7d;
        
        include /etc/nginx/snippets/proxy-params.conf;
        proxy_pass http://{SERVICE_NAME}_frontend;
    }
}
```

---

