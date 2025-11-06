# 5.5 Default конфигурация

# /opt/balancer/nginx/conf.d/streams.conf

# PostgreSQL
upstream postgresql_backend {
    server {POSTGRES_HOST}:{POSTGRES_PORT} max_fails=3 fail_timeout=30s;
}

server {
    listen 5432;
    listen [::]:5432;
    proxy_pass postgresql_backend;
    proxy_connect_timeout 10s;
    proxy_timeout 30m;
    
    # IP фильтрация для PostgreSQL
    # Разрешить доступ только с определенных IP
    # В stream контексте используется модуль stream_access
    # Примечание: для stream необходимо компилировать Nginx с --with-stream_geoip_module
    # Альтернатива - использовать UFW на уровне хоста
}

# CouchDB
upstream couchdb_backend {
    server {COUCHDB_HOST}:{COUCHDB_PORT} max_fails=3 fail_timeout=30s;
}

server {
    listen 5984;
    listen [::]:5984;
    proxy_pass couchdb_backend;
    proxy_connect_timeout 10s;
    proxy_timeout 30m;
}

# Примечание: IP фильтрация для TCP лучше делать через UFW:
# ufw allow from 192.168.1.0/24 to any port 5432 proto tcp
# ufw allow from 192.168.1.0/24 to any port 5984 proto tcp
```

```nginx
# /opt/balancer/nginx/conf.d/default.conf

# Default сервер для необработанных запросов
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # Let's Encrypt ACME challenge для всех доменов
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        allow all;
    }

    location / {
        return 444;  # Закрыть соединение без ответа
    }
}

server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name _;

    # Самоподписанный сертификат для default сервера
    # Создается при инициализации
    ssl_certificate /etc/nginx/snippets/self-signed.crt;
    ssl_certificate_key /etc/nginx/snippets/self-signed.key;

    include /etc/nginx/snippets/ssl-params.conf;

    return 444;
}
```

---

[◀ Назад к оглавлению](INDEX.md) | [Следующий раздел ▶](007a_init-script.md)
