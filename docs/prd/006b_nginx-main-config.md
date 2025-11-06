# 5.2 Nginx главный конфиг

# /opt/balancer/nginx/nginx.conf

user nginx;
worker_processes auto;
worker_rlimit_nofile 65535;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Формат логов с детальной информацией
    log_format detailed '$remote_addr - $remote_user [$time_local] '
                        '"$request" $status $body_bytes_sent '
                        '"$http_referer" "$http_user_agent" '
                        'rt=$request_time uct="$upstream_connect_time" '
                        'uht="$upstream_header_time" urt="$upstream_response_time" '
                        'host=$host scheme=$scheme';

    access_log /var/log/nginx/access.log detailed;

    # Базовые настройки производительности
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 100;
    reset_timedout_connection on;
    
    # Отключение версии Nginx
    server_tokens off;
    
    # Хеши и буферы
    types_hash_max_size 2048;
    server_names_hash_bucket_size 128;
    client_body_buffer_size 128k;
    client_max_body_size 100m;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 16k;

    # Таймауты
    client_body_timeout 30;
    client_header_timeout 30;
    send_timeout 30;
    proxy_connect_timeout 60;
    proxy_send_timeout 60;
    proxy_read_timeout 60;

    # Gzip сжатие
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 256;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/rss+xml
        application/atom+xml
        image/svg+xml
        text/x-component
        text/x-cross-domain-policy
        font/truetype
        font/opentype
        application/vnd.ms-fontobject
        application/x-font-ttf
        application/font-woff
        application/font-woff2;
    gzip_disable "msie6";

    # Кеширование статики
    proxy_cache_path /var/cache/nginx/static 
                     levels=1:2 
                     keys_zone=STATIC:50m 
                     inactive=7d 
                     max_size=1g 
                     use_temp_path=off;

    # Кеширование API ответов (опционально)
    proxy_cache_path /var/cache/nginx/api 
                     levels=1:2 
                     keys_zone=API:10m 
                     inactive=1h 
                     max_size=100m 
                     use_temp_path=off;

    # Ограничение запросов (rate limiting)
    limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=api:10m rate=30r/s;
    limit_req_status 429;
    
    # Ограничение соединений
    limit_conn_zone $binary_remote_addr zone=addr:10m;
    limit_conn addr 50;

    # WebSocket support
    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }

    # Загрузка конфигураций сервисов
    include /etc/nginx/conf.d/*.conf;
}

