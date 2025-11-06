# ПРД: Балансировщик и Reverse Proxy "Balancer"

## Версия документа: 2.0 FINAL
**Дата:** 06.11.2025  
**Статус:** Утверждено к реализации  
**Проект:** Balancer - Nginx Reverse Proxy System

---

## Содержание

1. [Executive Summary](#1-executive-summary)
2. [Архитектура системы](#2-архитектура-системы)
3. [Технические требования](#3-технические-требования)
4. [Структура проекта](#4-структура-проекта)
5. [Конфигурации](#5-конфигурации)
6. [Скрипты автоматизации](#6-скрипты-автоматизации)
7. [Развертывание](#7-развертывание)
8. [Эксплуатация](#8-эксплуатация)
9. [Troubleshooting](#9-troubleshooting)
10. [Приложения](#10-приложения)

---

## 1. Executive Summary

### 1.1 Цель проекта

Реализация централизованного reverse proxy на базе **Nginx** для управления доступом к Docker-контейнерам через HTTPS с автоматическим управлением SSL-сертификатами Let's Encrypt.

### 1.2 Ключевые возможности

- ✅ HTTPS доступ ко всем сервисам с автоматическими SSL сертификатами
- ✅ TCP проксирование для СУБД (PostgreSQL, CouchDB)
- ✅ Bash-скрипты для управления сервисами (добавление/удаление)
- ✅ Автоматическое обновление Let's Encrypt сертификатов
- ✅ Health checks и мониторинг сервисов
- ✅ Telegram алерты при проблемах
- ✅ IP-фильтрация для внутренних сервисов
- ✅ Graceful reload без downtime
- ✅ Кеширование статического контента

### 1.3 Целевые сервисы

| Сервис | Тип | Порт | Публичный доступ |
|--------|-----|------|------------------|
| PostgreSQL | СУБД | 5432 | Ограниченный (по IP) |
| CouchDB | NoSQL СУБД | 5984 | Ограниченный (по IP) |
| FastAPI | Backend API | 8000 | Да (HTTPS) |
| Frontend | Nginx Static | 80 | Да (HTTPS) |

### 1.4 Целевые метрики

- Время добавления сервиса: **< 5 минут**
- Uptime: **> 99.5%**
- Автообновление сертификатов: **без downtime**
- Максимальное количество одновременных пользователей: **50**

---

## 2. Архитектура системы

### 2.1 Общая схема

```mermaid
graph TB
    subgraph Internet
        U[Users/Clients]
    end
    
    subgraph "Server: UFW Firewall"
        FW[UFW<br/>Ports: 80, 443, 5432, 5984]
    end
    
    subgraph "Docker: Balancer Network"
        NX[Nginx Container<br/>Reverse Proxy + SSL]
        CB[Certbot Container<br/>SSL Management]
        HM[Health Monitor<br/>Checks + Alerts]
    end
    
    subgraph "Docker: Services Network"
        PG[(PostgreSQL)]
        CD[(CouchDB)]
        API[FastAPI Backend]
        FE[Frontend Nginx]
    end
    
    subgraph "External Services"
        LE[Let's Encrypt]
        TG[Telegram Bot API]
    end
    
    U -->|HTTP/HTTPS| FW
    FW --> NX
    
    NX -->|api.domain.ru| API
    NX -->|app.domain.ru| FE
    NX -->|db.domain.ru:5432| PG
    NX -->|couch.domain.ru:5984| CD
    
    CB -->|Renew Certs| LE
    CB -->|Share Volume| NX
    
    HM -->|Monitor| NX
    HM -->|Check Health| API
    HM -->|Check Health| FE
    HM -->|Send Alerts| TG
    
    style NX fill:#2196F3,stroke:#1976D2,color:#fff
    style CB fill:#4CAF50,stroke:#388E3C,color:#fff
    style HM fill:#FF9800,stroke:#F57C00,color:#fff
    style FW fill:#F44336,stroke:#D32F2F,color:#fff
```

### 2.2 Поток обработки HTTPS запроса

```mermaid
sequenceDiagram
    participant C as Client
    participant FW as UFW Firewall
    participant N as Nginx (SSL Termination)
    participant B as Backend Service
    participant H as Health Monitor
    
    C->>FW: HTTPS Request (443)
    FW->>N: Allow & Forward
    
    alt Health Check
        H->>B: Check /health endpoint
        B-->>H: 200 OK
    end
    
    N->>N: SSL Termination
    N->>N: Route by domain
    N->>N: Apply IP filtering
    
    N->>B: HTTP Request (internal)
    B->>B: Process request
    B-->>N: HTTP Response
    
    N->>N: Add security headers
    N->>N: Cache if static
    N-->>C: HTTPS Response
    
    alt Service Unavailable
        B--xN: Connection refused
        N-->>C: 502 Bad Gateway
        N->>H: Log error
        H->>H: Alert via Telegram
    end
```

### 2.3 Процесс добавления нового сервиса

```mermaid
flowchart TD
    Start([Запуск add-service.sh]) --> Input[Ввод параметров:<br/>- Имя сервиса<br/>- Домен<br/>- Тип HTTP/TCP<br/>- Backend host:port]
    
    Input --> ValidDomain{Валидация<br/>домена}
    ValidDomain -->|Ошибка| ErrorDomain[Вывод ошибки]
    ErrorDomain --> End1([Завершение])
    
    ValidDomain -->|OK| CheckDNS{Проверка<br/>DNS записи}
    CheckDNS -->|Не найдена| WarnDNS[Предупреждение]
    WarnDNS --> ConfirmDNS{Продолжить?}
    ConfirmDNS -->|Нет| End2([Отмена])
    ConfirmDNS -->|Да| AskIP
    
    CheckDNS -->|OK| AskIP[Запрос IP-фильтрации]
    AskIP --> Confirm[Подтверждение<br/>конфигурации]
    
    Confirm --> GenConfig[Генерация конфига<br/>из шаблона]
    
    GenConfig --> TypeCheck{Тип<br/>сервиса?}
    
    TypeCheck -->|HTTP| GetSSL[Получение SSL<br/>сертификата Certbot]
    GetSSL --> SSLSuccess{SSL OK?}
    SSLSuccess -->|Нет| SSLError[Удаление конфига<br/>Ошибка]
    SSLError --> End3([Завершение])
    
    SSLSuccess -->|Да| TestConfig
    TypeCheck -->|TCP| UpdateStream[Обновление<br/>streams.conf]
    UpdateStream --> TestConfig
    
    TestConfig[nginx -t] --> TestResult{Конфиг<br/>валиден?}
    TestResult -->|Нет| ConfigError[Вывод ошибок<br/>Откат изменений]
    ConfigError --> End4([Завершение])
    
    TestResult -->|Да| Reload[nginx -s reload]
    Reload --> ReloadOK{Reload<br/>успешен?}
    ReloadOK -->|Нет| ReloadError[Ошибка reload]
    ReloadError --> End5([Завершение])
    
    ReloadOK -->|Да| SendAlert[Отправка уведомления<br/>в Telegram]
    SendAlert --> Success[Вывод информации<br/>о доступности]
    Success --> End6([Успешно])
    
    style Start fill:#4CAF50,stroke:#388E3C,color:#fff
    style Success fill:#4CAF50,stroke:#388E3C,color:#fff
    style End6 fill:#4CAF50,stroke:#388E3C,color:#fff
    style ErrorDomain fill:#F44336,stroke:#D32F2F,color:#fff
    style SSLError fill:#F44336,stroke:#D32F2F,color:#fff
    style ConfigError fill:#F44336,stroke:#D32F2F,color:#fff
    style ReloadError fill:#F44336,stroke:#D32F2F,color:#fff
    style End1 fill:#9E9E9E,stroke:#757575,color:#fff
    style End2 fill:#9E9E9E,stroke:#757575,color:#fff
    style End3 fill:#9E9E9E,stroke:#757575,color:#fff
    style End4 fill:#9E9E9E,stroke:#757575,color:#fff
    style End5 fill:#9E9E9E,stroke:#757575,color:#fff
```

### 2.4 Процесс обновления SSL сертификатов

```mermaid
flowchart LR
    subgraph "Каждые 12 часов"
        Timer[Cron/Loop] --> Certbot
    end
    
    Certbot[Certbot Container] --> Check{Сертификат<br/>истекает<br/>< 30 дней?}
    
    Check -->|Нет| Skip[Пропустить]
    Skip --> Sleep[Sleep 12h]
    Sleep --> Timer
    
    Check -->|Да| Renew[Обновление через<br/>ACME Challenge]
    Renew --> WebRoot[/.well-known/<br/>acme-challenge/]
    WebRoot --> LE[Let's Encrypt<br/>Validation]
    
    LE --> LEResult{Валидация<br/>успешна?}
    LEResult -->|Нет| Error[Логирование ошибки]
    Error --> Alert[Отправка алерта<br/>в Telegram]
    Alert --> Sleep
    
    LEResult -->|Да| NewCert[Получение нового<br/>сертификата]
    NewCert --> SaveCert[Сохранение в<br/>/etc/letsencrypt]
    SaveCert --> Reload[Сигнал Nginx<br/>reload]
    Reload --> Success[✓ Обновлено]
    Success --> Sleep
    
    style Timer fill:#2196F3,stroke:#1976D2,color:#fff
    style Certbot fill:#4CAF50,stroke:#388E3C,color:#fff
    style Success fill:#4CAF50,stroke:#388E3C,color:#fff
    style Error fill:#F44336,stroke:#D32F2F,color:#fff
    style Alert fill:#FF9800,stroke:#F57C00,color:#fff
```

### 2.5 Docker сети и взаимодействие

```mermaid
graph TB
    subgraph "Docker Network: proxy_network (bridge)"
        direction LR
        NGINX[nginx-proxy<br/>172.20.0.2]
        CERTBOT[certbot<br/>172.20.0.3]
        HEALTH[healthcheck<br/>172.20.0.4]
        
        NGINX -.->|Health Check| HEALTH
        CERTBOT -.->|Shared Volume| NGINX
    end
    
    subgraph "Docker Network: services_network (bridge)"
        direction LR
        POSTGRES[(postgres<br/>172.21.0.2)]
        COUCHDB[(couchdb<br/>172.21.0.3)]
        FASTAPI[fastapi<br/>172.21.0.4]
        FRONTEND[frontend<br/>172.21.0.5]
    end
    
    subgraph "Docker Network: internal_network (internal)"
        direction LR
        POSTGRES_INT[(postgres<br/>172.22.0.2)]
        COUCHDB_INT[(couchdb<br/>172.22.0.3)]
    end
    
    NGINX -->|Proxy Pass| FASTAPI
    NGINX -->|Proxy Pass| FRONTEND
    NGINX -->|TCP Stream| POSTGRES
    NGINX -->|TCP Stream| COUCHDB
    
    FASTAPI -.->|Internal Access| POSTGRES_INT
    FASTAPI -.->|Internal Access| COUCHDB_INT
    
    style NGINX fill:#2196F3,stroke:#1976D2,color:#fff
    style CERTBOT fill:#4CAF50,stroke:#388E3C,color:#fff
    style HEALTH fill:#FF9800,stroke:#F57C00,color:#fff
```

### 2.6 Система мониторинга и алертов

```mermaid
flowchart TD
    Start([Запуск Health Monitor]) --> Interval[Интервал: 5 минут]
    
    Interval --> CheckNginx[Проверка Nginx<br/>docker exec nginx -t]
    CheckNginx --> NginxOK{Nginx OK?}
    NginxOK -->|Нет| AlertNginx[Алерт: Nginx Failed]
    AlertNginx --> TG1[Telegram]
    NginxOK -->|Да| LogNginx[Лог: Nginx OK]
    
    LogNginx --> CheckCerts[Проверка сертификатов<br/>срок действия]
    CheckCerts --> CertLoop{Для каждого<br/>сертификата}
    
    CertLoop --> CertExpiry{Истекает<br/>< 30 дней?}
    CertExpiry -->|Да| AlertCert[Алерт: Certificate<br/>Expiring Soon]
    AlertCert --> TG2[Telegram]
    CertExpiry -->|Нет| LogCert[Лог: Cert OK]
    
    LogCert --> CheckServices[Проверка сервисов<br/>HTTP запросы]
    CheckServices --> ServiceLoop{Для каждого<br/>сервиса}
    
    ServiceLoop --> HTTPCheck[curl -I https://domain]
    HTTPCheck --> HTTPResult{HTTP<br/>Status?}
    
    HTTPResult -->|5xx/000| AlertService[Алерт: Service Down]
    AlertService --> TG3[Telegram]
    HTTPResult -->|2xx/3xx| LogService[Лог: Service OK]
    
    LogService --> CheckDisk[Проверка диска<br/>df -h]
    CheckDisk --> DiskUsage{Использование<br/>> 90%?}
    DiskUsage -->|Да| AlertDisk[Алерт: Disk Space]
    AlertDisk --> TG4[Telegram]
    DiskUsage -->|Нет| LogDisk[Лог: Disk OK]
    
    TG1 --> Sleep
    TG2 --> Sleep
    TG3 --> Sleep
    TG4 --> Sleep
    LogDisk --> Sleep[Sleep 5 минут]
    Sleep --> Interval
    
    style Start fill:#4CAF50,stroke:#388E3C,color:#fff
    style AlertNginx fill:#F44336,stroke:#D32F2F,color:#fff
    style AlertCert fill:#FF9800,stroke:#F57C00,color:#fff
    style AlertService fill:#F44336,stroke:#D32F2F,color:#fff
    style AlertDisk fill:#FF9800,stroke:#F57C00,color:#fff
    style TG1 fill:#2196F3,stroke:#1976D2,color:#fff
    style TG2 fill:#2196F3,stroke:#1976D2,color:#fff
    style TG3 fill:#2196F3,stroke:#1976D2,color:#fff
    style TG4 fill:#2196F3,stroke:#1976D2,color:#fff
```

---

## 3. Технические требования

### 3.1 Системные требования

| Компонент | Минимум | Рекомендуется |
|-----------|---------|---------------|
| **ОС** | Ubuntu 22.04+ / Debian 10+ | Ubuntu 24.04 LTS |
| **CPU** | 2 cores | 4 cores |
| **RAM** | 2 GB | 4 GB |
| **Диск** | 20 GB | 50 GB (SSD) |
| **Docker** | 20.10+ | 24.0+ |
| **Docker Compose** | 2.0+ | 2.20+ |

### 3.2 Сетевые требования

| Порт | Протокол | Назначение | Доступ |
|------|----------|------------|--------|
| 80 | TCP | HTTP (redirect to HTTPS) | Public |
| 443 | TCP | HTTPS | Public |
| 5432 | TCP | PostgreSQL | Restricted by IP |
| 5984 | TCP | CouchDB | Restricted by IP |
| 22 | TCP | SSH | Admin only |

### 3.3 Внешние зависимости

- **Let's Encrypt API** - для получения SSL сертификатов
- **Telegram Bot API** - для отправки уведомлений
- **DNS сервер** - корректные A/CNAME записи для доменов

---

## 4. Структура проекта

### 4.1 Файловая структура

```
/opt/balancer/
├── docker-compose.yml              # Основной Docker Compose
├── .env                            # Переменные окружения (генерируется)
├── .env.example                    # Пример переменных
├── README.md                       # Документация
│
├── nginx/                          # Конфигурации Nginx
│   ├── nginx.conf                  # Главный конфиг
│   ├── conf.d/                     # Конфигурации сервисов
│   │   ├── default.conf            # Базовая страница
│   │   └── streams.conf            # TCP/UDP проксирование
│   ├── snippets/                   # Переиспользуемые блоки
│   │   ├── ssl-params.conf
│   │   ├── security-headers.conf
│   │   ├── proxy-params.conf
│   │   └── cache-params.conf
│   └── html/                       # Статические страницы
│       ├── 50x.html
│       └── index.html
│
├── certbot/                        # Let's Encrypt данные
│   └── conf/                       # Сертификаты (volume)
│
├── logs/                           # Логи
│   ├── nginx/
│   ├── certbot/
│   └── health-check.log
│
├── scripts/                        # Скрипты управления
│   ├── init-balancer.sh           # Первоначальная инициализация
│   ├── add-service.sh             # Добавление сервиса
│   ├── remove-service.sh          # Удаление сервиса
│   ├── health-check.sh            # Проверка здоровья
│   ├── telegram-alert.sh          # Отправка уведомлений
│   └── test-config.sh             # Тестирование конфигов
│
├── templates/                      # Шаблоны конфигураций
│   ├── service-http.conf.tmpl     # HTTP сервис
│   ├── service-tcp.conf.tmpl      # TCP сервис
│   └── service-fastapi.conf.tmpl  # FastAPI специфичный
│
└── healthcheck/                    # Health Monitor
    ├── Dockerfile
    ├── entrypoint.sh
    └── health-check.sh
```

---

## 5. Конфигурации

### 5.1 Docker Compose

```yaml
# /opt/balancer/docker-compose.yml
version: '3.8'

networks:
  proxy_network:
    name: proxy_network
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
  
  internal_network:
    name: internal_network
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 172.22.0.0/16

volumes:
  certbot_conf:
    name: certbot_conf
    driver: local
  certbot_www:
    name: certbot_www
    driver: local
  nginx_cache:
    name: nginx_cache
    driver: local

services:
  nginx:
    image: nginx:1.25-alpine
    container_name: nginx-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "5432:5432"   # PostgreSQL
      - "5984:5984"   # CouchDB
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/snippets:/etc/nginx/snippets:ro
      - ./nginx/html:/usr/share/nginx/html:ro
      - certbot_conf:/etc/letsencrypt:ro
      - certbot_www:/var/www/certbot:ro
      - nginx_cache:/var/cache/nginx
      - ./logs/nginx:/var/log/nginx
    networks:
      - proxy_network
      - internal_network
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 5s
    labels:
      - "com.balancer.description=Nginx Reverse Proxy"
      - "com.balancer.version=1.0"

  certbot:
    image: certbot/certbot:latest
    container_name: certbot
    restart: unless-stopped
    volumes:
      - certbot_conf:/etc/letsencrypt
      - certbot_www:/var/www/certbot
      - ./logs/certbot:/var/log/letsencrypt
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew --webroot -w /var/www/certbot --quiet --deploy-hook \"nginx -s reload\"; sleep 12h & wait $${!}; done;'"
    depends_on:
      nginx:
        condition: service_healthy
    networks:
      - proxy_network
    labels:
      - "com.balancer.description=SSL Certificate Manager"

  healthcheck:
    build: 
      context: ./healthcheck
      dockerfile: Dockerfile
    container_name: healthcheck-monitor
    restart: unless-stopped
    volumes:
      - ./scripts:/scripts:ro
      - certbot_conf:/etc/letsencrypt:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./logs:/logs
    environment:
      - TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
      - TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}
      - CHECK_INTERVAL=300
      - TZ=${TZ:-Europe/Moscow}
    networks:
      - proxy_network
    depends_on:
      nginx:
        condition: service_healthy
    labels:
      - "com.balancer.description=Health Monitor"
```

### 5.2 Nginx главный конфиг

```nginx
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

### 5.3 Snippets (переиспользуемые блоки)

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
# /opt/balancer/nginx/snippets/cache-params.conf

# Кеширование статических файлов
location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot|otf|webp|avif)$ {
    proxy_cache STATIC;
    proxy_cache_valid 200 7d;
    proxy_cache_valid 404 1m;
    proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
    proxy_cache_background_update on;
    proxy_cache_lock on;
    proxy_cache_revalidate on;
    
    add_header X-Cache-Status $upstream_cache_status;
    expires 7d;
    access_log off;
    
    include /etc/nginx/snippets/proxy-params.conf;
    proxy_pass http://$backend;
}
```

### 5.4 Шаблоны конфигураций сервисов

#### 5.4.1 FastAPI сервис

```nginx
# /opt/balancer/templates/service-fastapi.conf.tmpl

# Upstream для {SERVICE_NAME}
upstream {SERVICE_NAME}_backend {
    server {BACKEND_HOST}:{BACKEND_PORT} max_fails=3 fail_timeout=30s;
    keepalive 32;
    keepalive_requests 100;
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

# HTTPS сервер
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

    # Логи для сервиса
    access_log /var/log/nginx/{SERVICE_NAME}-access.log detailed;
    error_log /var/log/nginx/{SERVICE_NAME}-error.log warn;

    # IP фильтрация (опционально, раскомментировать при необходимости)
    # allow 192.168.1.0/24;
    # allow 10.0.0.0/8;
    # deny all;

    # Rate limiting для API
    limit_req zone=api burst=50 nodelay;

    # Основной location для API
    location / {
        include /etc/nginx/snippets/proxy-params.conf;
        proxy_pass http://{SERVICE_NAME}_backend;

        # Обработка ошибок upstream
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;
        proxy_next_upstream_tries 2;
        proxy_next_upstream_timeout 5s;
    }

    # Health check endpoint (FastAPI)
    location /health {
        access_log off;
        include /etc/nginx/snippets/proxy-params.conf;
        proxy_pass http://{SERVICE_NAME}_backend/health;
    }

    # OpenAPI документация (опционально ограничить по IP)
    location /docs {
        # allow 192.168.1.0/24;
        # deny all;
        include /etc/nginx/snippets/proxy-params.conf;
        proxy_pass http://{SERVICE_NAME}_backend/docs;
    }

    location /redoc {
        # allow 192.168.1.0/24;
        # deny all;
        include /etc/nginx/snippets/proxy-params.conf;
        proxy_pass http://{SERVICE_NAME}_backend/redoc;
    }

    location /openapi.json {
        # allow 192.168.1.0/24;
        # deny all;
        include /etc/nginx/snippets/proxy-params.conf;
        proxy_pass http://{SERVICE_NAME}_backend/openapi.json;
    }

    # WebSocket support для FastAPI
    location /ws {
        include /etc/nginx/snippets/proxy-params.conf;
        proxy_pass http://{SERVICE_NAME}_backend;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        
        proxy_read_timeout 86400;
    }

    # Отключение кеширования для API (можно включить для GET запросов)
    # location ~ ^/api/v1/(readonly|public)/ {
    #     proxy_cache API;
    #     proxy_cache_valid 200 5m;
    #     proxy_cache_methods GET HEAD;
    #     proxy_cache_key "$scheme$request_method$host$request_uri";
    #     
    #     add_header X-Cache-Status $upstream_cache_status;
    #     
    #     include /etc/nginx/snippets/proxy-params.conf;
    #     proxy_pass http://{SERVICE_NAME}_backend;
    # }
}
```

#### 5.4.2 Frontend (Nginx Static)

```nginx
# /opt/balancer/templates/service-frontend.conf.tmpl

# Upstream для {SERVICE_NAME}
upstream {SERVICE_NAME}_backend {
    server {BACKEND_HOST}:{BACKEND_PORT} max_fails=3 fail_timeout=30s;
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

# HTTPS сервер
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
    access_log /var/log/nginx/{SERVICE_NAME}-access.log detailed;
    error_log /var/log/nginx/{SERVICE_NAME}-error.log warn;

    # Rate limiting
    limit_req zone=general burst=20 nodelay;

    # Основной location
    location / {
        include /etc/nginx/snippets/proxy-params.conf;
        proxy_pass http://{SERVICE_NAME}_backend;
    }

    # Кеширование статических файлов
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot|otf|webp|avif|mp4|webm)$ {
        proxy_cache STATIC;
        proxy_cache_valid 200 7d;
        proxy_cache_valid 404 1m;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_cache_background_update on;
        proxy_cache_lock on;
        
        add_header X-Cache-Status $upstream_cache_status;
        add_header Cache-Control "public, max-age=604800, immutable";
        
        expires 7d;
        access_log off;
        
        include /etc/nginx/snippets/proxy-params.conf;
        proxy_pass http://{SERVICE_NAME}_backend;
    }

    # Manifest и service worker
    location ~* \.(manifest|json|webmanifest)$ {
        include /etc/nginx/snippets/proxy-params.conf;
        proxy_pass http://{SERVICE_NAME}_backend;
        
        add_header Cache-Control "public, max-age=3600";
        expires 1h;
    }

    # Service Worker не кешируется
    location = /service-worker.js {
        include /etc/nginx/snippets/proxy-params.conf;
        proxy_pass http://{SERVICE_NAME}_backend;
        
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        expires -1;
    }

    # SPA fallback (для React/Vue/Angular)
    location @fallback {
        include /etc/nginx/snippets/proxy-params.conf;
        proxy_pass http://{SERVICE_NAME}_backend/index.html;
    }

    # Обработка несуществующих путей для SPA
    error_page 404 = @fallback;
}
```

#### 5.4.3 TCP Stream для баз данных

```nginx
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

### 5.5 Default конфигурация

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

## 6. Скрипты автоматизации

### 6.1 Скрипт инициализации

```bash
#!/bin/bash
# /opt/balancer/scripts/init-balancer.sh
# Первоначальная инициализация системы Balancer

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Balancer Initialization Script      ║${NC}"
echo -e "${BLUE}║   Nginx Reverse Proxy Setup           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Ошибка: Требуются права root${NC}"
    echo "Запустите: sudo bash $0"
    exit 1
fi

# Функция для проверки зависимостей
check_dependencies() {
    echo -e "${YELLOW}Проверка зависимостей...${NC}"
    
    local deps=("docker" "docker-compose" "curl" "openssl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            missing+=($dep)
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}Отсутствуют зависимости: ${missing[*]}${NC}"
        echo -e "${YELLOW}Установить автоматически? (y/n)${NC}"
        read -r confirm
        if [ "$confirm" == "y" ]; then
            install_dependencies
        else
            exit 1
        fi
    else
        echo -e "${GREEN}✓ Все зависимости установлены${NC}"
    fi
}

# Функция установки зависимостей
install_dependencies() {
    echo -e "${YELLOW}Установка зависимостей...${NC}"
    
    # Обновление пакетов
    apt-get update
    
    # Установка базовых утилит
    apt-get install -y curl openssl ca-certificates gnupg lsb-release
    
    # Установка Docker если отсутствует
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Установка Docker...${NC}"
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh
        rm /tmp/get-docker.sh
        systemctl enable docker
        systemctl start docker
    fi
    
    # Установка Docker Compose Plugin
    if ! docker compose version &> /dev/null; then
        echo -e "${YELLOW}Установка Docker Compose Plugin...${NC}"
        apt-get install -y docker-compose-plugin
    fi
    
    echo -e "${GREEN}✓ Зависимости установлены${NC}"
}

# Функция для сбора конфигурации
collect_configuration() {
    echo -e "\n${BLUE}═══ Конфигурация параметров ═══${NC}\n"
    
    # Email для Let's Encrypt
    while true; do
        read -p "Email для Let's Encrypt уведомлений: " LETSENCRYPT_EMAIL
        if [[ "$LETSENCRYPT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo -e "${RED}Некорректный email формат${NC}"
        fi
    done
    
    # Telegram Bot Token
    echo -e "\n${YELLOW}Для получения Telegram Bot Token:${NC}"
    echo "1. Откройте @BotFather в Telegram"
    echo "2. Отправьте команду /newbot"
    echo "3. Следуйте инструкциям"
    echo "4. Скопируйте полученный token"
    read -p "Telegram Bot Token: " TELEGRAM_BOT_TOKEN
    
    # Telegram Chat ID
    echo -e "\n${YELLOW}Для получения Chat ID:${NC}"
    echo "1. Откройте @userinfobot в Telegram"
    echo "2. Отправьте любое сообщение"
    echo "3. Скопируйте ваш ID"
    read -p "Telegram Chat ID: " TELEGRAM_CHAT_ID
    
    # Timezone
    echo -e "\n${YELLOW}Доступные временные зоны:${NC}"
    echo "1. Europe/Moscow"
    echo "2. Europe/London"
    echo "3. America/New_York"
    echo "4. Asia/Tokyo"
    echo "5. Другая (ввести вручную)"
    read -p "Выбор (1-5): " tz_choice
    
    case $tz_choice in
        1) TZ="Europe/Moscow";;
        2) TZ="Europe/London";;
        3) TZ="America/New_York";;
        4) TZ="Asia/Tokyo";;
        5) read -p "Введите timezone: " TZ;;
        *) TZ="Europe/Moscow";;
    esac
    
    echo -e "\n${GREEN}═══ Конфигурация собрана ═══${NC}"
}

# Функция создания .env файла
create_env_file() {
    echo -e "\n${YELLOW}Создание .env файла...${NC}"
    
    cat > "$PROJECT_DIR/.env" << EOF
# Balancer Configuration
# Generated: $(date)

# Let's Encrypt
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL

# Telegram Alerts
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID

# System
TZ=$TZ

# Docker Compose Project
COMPOSE_PROJECT_NAME=balancer
EOF
    
    chmod 600 "$PROJECT_DIR/.env"
    echo -e "${GREEN}✓ .env файл создан${NC}"
}

# Функция создания самоподписанного сертификата
create_self_signed_cert() {
    echo -e "\n${YELLOW}Создание самоподписанного сертификата для default сервера...${NC}"
    
    mkdir -p "$PROJECT_DIR/nginx/snippets"
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$PROJECT_DIR/nginx/snippets/self-signed.key" \
        -out "$PROJECT_DIR/nginx/snippets/self-signed.crt" \
        -subj "/C=RU/ST=Moscow/L=Moscow/O=Balancer/CN=default" \
        2>/dev/null
    
    echo -e "${GREEN}✓ Самоподписанный сертификат создан${NC}"
}

# Функция настройки UFW
setup_firewall() {
    echo -e "\n${YELLOW}Настройка UFW Firewall...${NC}"
    
    if ! command -v ufw &> /dev/null; then
        echo -e "${YELLOW}Установка UFW...${NC}"
        apt-get install -y ufw
    fi
    
    # Сброс правил
    ufw --force reset
    
    # Базовые политики
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH (текущий порт)
    SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | cut -d':' -f2 | head -1)
    [ -z "$SSH_PORT" ] && SSH_PORT=22
    ufw allow $SSH_PORT/tcp comment 'SSH'
    
    # HTTP/HTTPS
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    
    echo -e "${YELLOW}Открыть порты для баз данных? (5432, 5984)${NC}"
    echo "Рекомендуется ограничить доступ по IP позже"
    read -p "Открыть? (y/n): " open_db_ports
    
    if [ "$open_db_ports" == "y" ]; then
        ufw allow 5432/tcp comment 'PostgreSQL'
        ufw allow 5984/tcp comment 'CouchDB'
        echo -e "${YELLOW}⚠ Не забудьте настроить IP-фильтрацию позже!${NC}"
    fi
    
    # Включение UFW
    ufw --force enable
    
    echo -e "${GREEN}✓ UFW настроен${NC}"
    ufw status verbose
}

# Функция настройки Fail2Ban
setup_fail2ban() {
    echo -e "\n${YELLOW}Настроить Fail2Ban для дополнительной защиты? (y/n)${NC}"
    read -p "> " setup_f2b
    
    if [ "$setup_f2b" != "y" ]; then
        echo "Пропуск Fail2Ban"
        return
    fi
    
    if ! command -v fail2ban-server &> /dev/null; then
        echo -e "${YELLOW}Установка Fail2Ban...${NC}"
        apt-get install -y fail2ban
    fi
    
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
port = http,https
logpath = /opt/balancer/logs/nginx/*error.log

[nginx-limit-req]
enabled = true
port = http,https
logpath = /opt/balancer/logs/nginx/*error.log
maxretry = 10
EOF
    
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    echo -e "${GREEN}✓ Fail2Ban настроен${NC}"
}

# Функция создания структуры каталогов
create_directory_structure() {
    echo -e "\n${YELLOW}Создание структуры каталогов...${NC}"
    
    mkdir -p "$PROJECT_DIR"/{nginx/{conf.d,snippets,html},certbot/conf,logs/{nginx,certbot},scripts,templates,healthcheck}
    
    # Установка прав
    chown -R root:root "$PROJECT_DIR"
    chmod -R 755 "$PROJECT_DIR"
    chmod -R 755 "$PROJECT_DIR/scripts"
    
    echo -e "${GREEN}✓ Структура каталогов создана${NC}"
}

# Функция создания systemd сервиса
create_systemd_service() {
    echo -e "\n${YELLOW}Создание systemd сервиса...${NC}"
    
    cat > /etc/systemd/system/balancer.service << EOF
[Unit]
Description=Balancer - Nginx Reverse Proxy System
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart
TimeoutStartSec=0
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable balancer.service
    
    echo -e "${GREEN}✓ Systemd сервис создан и включен${NC}"
}

# Функция тестирования Telegram
test_telegram() {
    echo -e "\n${YELLOW}Тестирование Telegram уведомлений...${NC}"
    
    MESSAGE="🚀 Balancer инициализирован!%0A%0AHost: $(hostname)%0ATime: $(date '+%Y-%m-%d %H:%M:%S')"
    
    RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${MESSAGE}" \
        -d "parse_mode=HTML")
    
    if echo "$RESPONSE" | grep -q '"ok":true'; then
        echo -e "${GREEN}✓ Telegram уведомления работают${NC}"
    else
        echo -e "${RED}✗ Ошибка отправки в Telegram${NC}"
        echo "Проверьте токен и chat_id"
    fi
}

# Функция запуска контейнеров
start_containers() {
    echo -e "\n${YELLOW}Запуск Docker контейнеров...${NC}"
    
    cd "$PROJECT_DIR"
    docker compose up -d
    
    echo -e "${YELLOW}Ожидание запуска контейнеров...${NC}"
    sleep 10
    
    # Проверка статуса
    docker compose ps
    
    if docker compose ps | grep -q "Up"; then
        echo -e "${GREEN}✓ Контейнеры запущены${NC}"
    else
        echo -e "${RED}✗ Ошибка запуска контейнеров${NC}"
        docker compose logs
        exit 1
    fi
}

# Функция вывода итоговой информации
print_summary() {
    echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   Инициализация завершена успешно!     ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"
    
    echo -e "${BLUE}Следующие шаги:${NC}"
    echo -e "1. Создайте DNS записи для ваших доменов"
    echo -e "2. Добавьте сервисы командой:"
    echo -e "   ${YELLOW}bash $PROJECT_DIR/scripts/add-service.sh${NC}"
    echo -e "3. Настройте IP-фильтрацию для БД через UFW:"
    echo -e "   ${YELLOW}ufw delete allow 5432/tcp${NC}"
    echo -e "   ${YELLOW}ufw allow from <IP>/24 to any port 5432 proto tcp${NC}"
    
    echo -e "\n${BLUE}Полезные команды:${NC}"
    echo -e "  Статус:     ${YELLOW}systemctl status balancer${NC}"
    echo -e "  Логи:       ${YELLOW}docker compose logs -f${NC}"
    echo -e "  Перезапуск: ${YELLOW}systemctl restart balancer${NC}"
    
    echo -e "\n${BLUE}Документация: ${YELLOW}$PROJECT_DIR/README.md${NC}\n"
}

# Основная функция
main() {
    check_dependencies
    collect_configuration
    create_directory_structure
    create_env_file
    create_self_signed_cert
    setup_firewall
    setup_fail2ban
    create_systemd_service
    start_containers
    test_telegram
    print_summary
}

# Запуск
main
```

### 6.2 Скрипт добавления сервиса

```bash
#!/bin/bash
# /opt/balancer/scripts/add-service.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NGINX_CONF_DIR="$PROJECT_DIR/nginx/conf.d"
TEMPLATES_DIR="$PROJECT_DIR/templates"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Добавление нового сервиса          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"

# Загрузка переменных окружения
if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    echo -e "${RED}Ошибка: .env файл не найден${NC}"
    exit 1
fi

# Функция валидации домена
validate_domain() {
    local domain=$1
    if [[ ! $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        echo -e "${RED}Ошибка: Некорректный формат домена${NC}"
        return 1
    fi
    return 0
}

# Функция проверки DNS
check_dns() {
    local domain=$1
    echo -e "${YELLOW}Проверка DNS записи для $domain...${NC}"
    
    if host $domain > /dev/null 2>&1; then
        local ip=$(host $domain | awk '/has address/ { print $4 }' | head -1)
        local server_ip=$(curl -s ifconfig.me || curl -s icanhazip.com)
        
        echo "DNS указывает на: $ip"
        echo "IP сервера: $server_ip"
        
        if [ "$ip" == "$server_ip" ]; then
            echo -e "${GREEN}✓ DNS запись корректна${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ DNS и IP сервера не совпадают${NC}"
            read -p "Продолжить? (y/n): " confirm
            [ "$confirm" != "y" ] && return 1
        fi
    else
        echo -e "${YELLOW}⚠ DNS запись не найдена${NC}"
        read -p "Продолжить без DNS? (y/n): " confirm
        [ "$confirm" != "y" ] && return 1
    fi
    return 0
}

# Сбор информации
echo -e "${BLUE}═══ Параметры сервиса ═══${NC}\n"

read -p "Имя сервиса (латиница, без пробелов): " SERVICE_NAME
SERVICE_NAME=$(echo "$SERVICE_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_-')

read -p "Поддомен (например: api): " SUBDOMAIN
read -p "Основной домен (например: example.ru): " MAIN_DOMAIN
DOMAIN="${SUBDOMAIN}.${MAIN_DOMAIN}"

validate_domain "$DOMAIN" || exit 1

echo -e "\n${YELLOW}Типы сервисов:${NC}"
echo "1. FastAPI Backend"
echo "2. Frontend (Static/Nginx)"
echo "3. Custom HTTP"
echo "4. TCP (Database)"
read -p "Выберите тип (1-4): " SERVICE_TYPE_CHOICE

case $SERVICE_TYPE_CHOICE in
    1) SERVICE_TYPE="fastapi";;
    2) SERVICE_TYPE="frontend";;
    3) SERVICE_TYPE="http";;
    4) SERVICE_TYPE="tcp";;
    *) echo -e "${RED}Некорректный выбор${NC}"; exit 1;;
esac

read -p "Хост бэкенда (имя Docker контейнера): " BACKEND_HOST
read -p "Порт бэкенда: " BACKEND_PORT

if [ "$SERVICE_TYPE" == "tcp" ]; then
    read -p "Внешний TCP порт: " EXTERNAL_PORT
    read -p "Разрешить доступ только с определенных IP? (y/n): " RESTRICT_IP
    if [ "$RESTRICT_IP" == "y" ]; then
        read -p "Разрешенная подсеть (например: 192.168.1.0/24): " ALLOWED_SUBNET
    fi
else
    read -p "Включить IP-фильтрацию? (y/n): " IP_FILTER
    if [ "$IP_FILTER" == "y" ]; then
        read -p "Разрешенная подсеть: " ALLOWED_SUBNET
    fi
fi

# Проверка DNS
check_dns "$DOMAIN" || exit 1

# Подтверждение
echo -e "\n${BLUE}═══ Подтверждение ═══${NC}"
echo "Имя сервиса: $SERVICE_NAME"
echo "Домен: $DOMAIN"
echo "Тип: $SERVICE_TYPE"
echo "Бэкенд: $BACKEND_HOST:$BACKEND_PORT"
[ "$SERVICE_TYPE" == "tcp" ] && echo "Внешний порт: $EXTERNAL_PORT"
echo ""
read -p "Подтвердите создание (yes/no): " CONFIRM
[ "$CONFIRM" != "yes" ] && { echo -e "${RED}Отменено${NC}"; exit 0; }

# Создание конфигурации
echo -e "\n${YELLOW}Создание конфигурации...${NC}"

if [ "$SERVICE_TYPE" != "tcp" ]; then
    # HTTP/HTTPS конфигурация
    CONFIG_FILE="$NGINX_CONF_DIR/${SERVICE_NAME}.conf"
    
    # Выбор шаблона
    if [ "$SERVICE_TYPE" == "fastapi" ]; then
        TEMPLATE="$TEMPLATES_DIR/service-fastapi.conf.tmpl"
    elif [ "$SERVICE_TYPE" == "frontend" ]; then
        TEMPLATE="$TEMPLATES_DIR/service-frontend.conf.tmpl"
    else
        TEMPLATE="$TEMPLATES_DIR/service-http.conf.tmpl"
    fi
    
    # Генерация конфига
    sed -e "s/{SERVICE_NAME}/$SERVICE_NAME/g" \
        -e "s/{DOMAIN}/$DOMAIN/g" \
        -e "s/{BACKEND_HOST}/$BACKEND_HOST/g" \
        -e "s/{BACKEND_PORT}/$BACKEND_PORT/g" \
        "$TEMPLATE" > "$CONFIG_FILE"
    
    # IP-фильтрация
    if [ "$IP_FILTER" == "y" ]; then
        sed -i "/# IP фильтрация/a\    allow $ALLOWED_SUBNET;\n    deny all;" "$CONFIG_FILE"
    fi
    
    echo -e "${GREEN}✓ Конфиг создан: $CONFIG_FILE${NC}"
    
    # Получение SSL сертификата
    echo -e "\n${YELLOW}Получение SSL сертификата...${NC}"
    
    docker compose -f "$PROJECT_DIR/docker-compose.yml" run --rm certbot \
        certonly --webroot -w /var/www/certbot \
        --email "$LETSENCRYPT_EMAIL" \
        --agree-tos \
        --no-eff-email \
        -d "$DOMAIN" \
        --non-interactive || {
            echo -e "${RED}✗ Ошибка получения SSL${NC}"
            rm "$CONFIG_FILE"
            exit 1
        }
    
    echo -e "${GREEN}✓ SSL сертификат получен${NC}"
    
else
    # TCP Stream конфигурация
    STREAM_CONF="$NGINX_CONF_DIR/streams.conf"
    
    cat >> "$STREAM_CONF" << EOF

# $SERVICE_NAME - $DOMAIN
upstream ${SERVICE_NAME}_backend {
    server ${BACKEND_HOST}:${BACKEND_PORT} max_fails=3 fail_timeout=30s;
}

server {
    listen ${EXTERNAL_PORT};
    listen [::]:${EXTERNAL_PORT};
    proxy_pass ${SERVICE_NAME}_backend;
    proxy_connect_timeout 10s;
    proxy_timeout 30m;
}
EOF
    
    echo -e "${GREEN}✓ TCP stream добавлен${NC}"
    
    # Настройка UFW для TCP
    if [ "$RESTRICT_IP" == "y" ]; then
        echo -e "${YELLOW}Настройка UFW...${NC}"
        ufw allow from "$ALLOWED_SUBNET" to any port "$EXTERNAL_PORT" proto tcp comment "$SERVICE_NAME"
        echo -e "${GREEN}✓ UFW правило добавлено${NC}"
    else
        echo -e "${YELLOW}⚠ Не забудьте открыть порт $EXTERNAL_PORT в docker-compose.yml${NC}"
    fi
fi

# Проверка конфигурации
echo -e "\n${YELLOW}Проверка конфигурации Nginx...${NC}"
docker exec nginx-proxy nginx -t || {
    echo -e "${RED}✗ Ошибка в конфигурации${NC}"
    [ -f "$CONFIG_FILE" ] && rm "$CONFIG_FILE"
    exit 1
}
echo -e "${GREEN}✓ Конфигурация валидна${NC}"

# Перезагрузка Nginx
echo -e "\n${YELLOW}Перезагрузка Nginx...${NC}"
docker exec nginx-proxy nginx -s reload || {
    echo -e "${RED}✗ Ошибка перезагрузки${NC}"
    exit 1
}
echo -e "${GREEN}✓ Nginx перезагружен${NC}"

# Отправка уведомления
bash "$SCRIPT_DIR/telegram-alert.sh" "✅ Новый сервис добавлен\n\nСервис: $SERVICE_NAME\nДомен: $DOMAIN\nТип: $SERVICE_TYPE" 2>/dev/null || true

# Итоговая информация
echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Сервис успешно добавлен!          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"

if [ "$SERVICE_TYPE" != "tcp" ]; then
    echo -e "Доступен по адресу: ${GREEN}https://$DOMAIN${NC}"
    echo -e "Проверка: ${YELLOW}curl -I https://$DOMAIN${NC}"
else
    echo -e "Доступен по порту: ${GREEN}$EXTERNAL_PORT${NC}"
    echo -e "Проверка: ${YELLOW}telnet $MAIN_DOMAIN $EXTERNAL_PORT${NC}"
fi

echo -e "\nЛоги: ${YELLOW}tail -f $PROJECT_DIR/logs/nginx/${SERVICE_NAME}-*.log${NC}"
```

### 6.3 Скрипт удаления сервиса

```bash
#!/bin/bash
# /opt/balancer/scripts/remove-service.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NGINX_CONF_DIR="$PROJECT_DIR/nginx/conf.d"

echo -e "${RED}╔════════════════════════════════════════╗${NC}"
echo -e "${RED}║       Удаление сервиса                 ║${NC}"
echo -e "${RED}╚════════════════════════════════════════╝${NC}\n"

# Список конфигов
echo -e "${YELLOW}Доступные сервисы:${NC}\n"
configs=($(ls "$NGINX_CONF_DIR" | grep -v "default.conf\|streams.conf"))

if [ ${#configs[@]} -eq 0 ]; then
    echo -e "${YELLOW}Нет доступных сервисов для удаления${NC}"
    exit 0
fi

for i in "${!configs[@]}"; do
    printf "%2d) %s\n" $((i+1)) "${configs[$i]}"
done

echo ""
read -p "Выберите номер сервиса для удаления: " choice

if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#configs[@]}" ]; then
    echo -e "${RED}Некорректный выбор${NC}"
    exit 1
fi

CONFIG_FILE="${configs[$((choice-1))]}"
SERVICE_NAME=$(basename "$CONFIG_FILE" .conf)

# Извлечение домена
if [ -f "$NGINX_CONF_DIR/$CONFIG_FILE" ]; then
    DOMAIN=$(grep -oP 'server_name\s+\K[^;]+' "$NGINX_CONF_DIR/$CONFIG_FILE" | head -1 | tr -d ' ')
fi

echo -e "\n${RED}═══ Внимание! ═══${NC}"
echo "Будет удалено:"
echo "  Сервис: $SERVICE_NAME"
echo "  Домен: $DOMAIN"
echo "  Конфиг: $CONFIG_FILE"
echo ""

read -p "Удалить SSL сертификаты? (y/n): " DELETE_CERTS
read -p "Для подтверждения введите 'DELETE': " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    echo -e "${YELLOW}Отменено${NC}"
    exit 0
fi

# Удаление конфигурации
rm "$NGINX_CONF_DIR/$CONFIG_FILE"
echo -e "${GREEN}✓ Конфигурация удалена${NC}"

# Удаление сертификатов
if [ "$DELETE_CERTS" == "y" ] && [ -n "$DOMAIN" ]; then
    docker compose -f "$PROJECT_DIR/docker-compose.yml" run --rm certbot \
        delete --cert-name "$DOMAIN" --non-interactive 2>/dev/null || true
    echo -e "${GREEN}✓ Сертификаты удалены${NC}"
fi

# Проверка и перезагрузка
docker exec nginx-proxy nginx -t && docker exec nginx-proxy nginx -s reload

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Nginx перезагружен${NC}"
    
    # Уведомление
    bash "$SCRIPT_DIR/telegram-alert.sh" "🗑 Сервис удален\n\nСервис: $SERVICE_NAME\nДомен: $DOMAIN" 2>/dev/null || true
    
    echo -e "\n${GREEN}Сервис успешно удален${NC}"
else
    echo -e "${RED}✗ Ошибка перезагрузки Nginx${NC}"
fi
```

### 6.4 Health Check скрипт

```bash
#!/bin/bash
# /opt/balancer/scripts/health-check.sh

LOG_FILE="/logs/health-check.log"
NGINX_CONF_DIR="/etc/nginx/conf.d"
CERTBOT_CONF_DIR="/etc/letsencrypt"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

send_alert() {
    bash /scripts/telegram-alert.sh "$1" 2>/dev/null || true
}

# Проверка Nginx
check_nginx() {
    if ! nginx -t > /dev/null 2>&1; then
        send_alert "⚠️ Nginx configuration test failed!"
        log "✗ Nginx config failed"
        return 1
    fi
    
    if ! pgrep -x nginx > /dev/null; then
        send_alert "🚨 Nginx process not running!"
        log "✗ Nginx not running"
        return 1
    fi
    
    log "✓ Nginx healthy"
    return 0
}

# Проверка сертификатов
check_certificates() {
    local warning_days=30
    local now=$(date +%s)
    local alerts=()
    
    for cert_dir in "$CERTBOT_CONF_DIR/live"/*; do
        if [ -d "$cert_dir" ] && [ "$(basename "$cert_dir")" != "README" ]; then
            local domain=$(basename "$cert_dir")
            local cert_file="$cert_dir/fullchain.pem"
            
            if [ -f "$cert_file" ]; then
                local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                if [ -n "$expiry_date" ]; then
                    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null)
                    local days_left=$(( ($expiry_epoch - $now) / 86400 ))
                    
                    if [ $days_left -lt 0 ]; then
                        alerts+=("❌ Сертификат ИСТЕК: $domain")
                        log "✗ Certificate expired: $domain"
                    elif [ $days_left -lt $warning_days ]; then
                        alerts+=("⚠️ Сертификат истекает: $domain ($days_left дней)")
                        log "⚠ Certificate expiring: $domain ($days_left days)"
                    else
                        log "✓ Certificate OK: $domain ($days_left days)"
                    fi
                fi
            fi
        fi
    done
    
    if [ ${#alerts[@]} -gt 0 ]; then
        local message=$(IFS=$'\n'; echo "${alerts[*]}")
        send_alert "$message"
    fi
}

# Проверка сервисов
check_services() {
    local failed_services=()
    
    for conf_file in "$NGINX_CONF_DIR"/*.conf; do
        if [ -f "$conf_file" ] && [[ "$(basename "$conf_file")" != "default.conf" ]] && [[ "$(basename "$conf_file")" != "streams.conf" ]]; then
            local domain=$(grep -oP 'server_name\s+\K[^;]+' "$conf_file" 2>/dev/null | head -1 | tr -d ' ')
            
            if [ -n "$domain" ]; then
                local response=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$domain" --max-time 10 --connect-timeout 5 2>/dev/null || echo "000")
                
                if [ "$response" == "000" ]; then
                    failed_services+=("❌ Недоступен: $domain")
                    log "✗ Service unreachable: $domain"
                elif [ "$response" -ge 500 ]; then
                    failed_services+=("⚠️ Ошибка сервера: $domain (HTTP $response)")
                    log "✗ Service error: $domain (HTTP $response)"
                else
                    log "✓ Service OK: $domain (HTTP $response)"
                fi
            fi
        fi
    done
    
    if [ ${#failed_services[@]} -gt 0 ]; then
        local message=$(IFS=$'\n'; echo "${failed_services[*]}")
        send_alert "$message"
    fi
}

# Проверка диска
check_disk_space() {
    local threshold=90
    local usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$usage" -gt "$threshold" ]; then
        send_alert "💾 Критично мало места на диске: ${usage}%"
        log "✗ Disk space critical: ${usage}%"
    else
        log "✓ Disk space OK: ${usage}%"
    fi
}

# Основная функция
main() {
    log "=== Health check started ==="
    
    check_nginx
    check_certificates
    check_services
    check_disk_space
    
    log "=== Health check completed ==="
}

main
```

### 6.5 Telegram Alert скрипт

```bash
#!/bin/bash
# /opt/balancer/scripts/telegram-alert.sh

MESSAGE="$1"

if [ -z "$MESSAGE" ]; then
    echo "Usage: $0 \"message\""
    exit 1
fi

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo "Error: TELEGRAM credentials not set"
    exit 1
fi

HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")

FULL_MESSAGE="🖥 <b>Host:</b> $HOSTNAME%0A"
FULL_MESSAGE+="🌐 <b>IP:</b> $SERVER_IP%0A"
FULL_MESSAGE+="⏰ <b>Time:</b> $TIMESTAMP%0A%0A"
FULL_MESSAGE+="$MESSAGE"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=${FULL_MESSAGE}" \
    -d "parse_mode=HTML" \
    > /dev/null 2>&1

exit $?
```

### 6.6 Healthcheck Dockerfile

```dockerfile
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

## 7. Развертывание

### 7.1 Подготовка сервера

```bash
# 1. Обновление системы
sudo apt update && sudo apt upgrade -y

# 2. Установка базовых утилит
sudo apt install -y curl wget git vim htop net-tools

# 3. Клонирование или создание структуры
sudo mkdir -p /opt/balancer
cd /opt/balancer

# 4. Копирование всех файлов из документации
# (структура каталогов, конфиги, скрипты)
```

### 7.2 Запуск инициализации

```bash
# Запуск скрипта инициализации
cd /opt/balancer
sudo bash scripts/init-balancer.sh
```

Скрипт выполнит:
- ✅ Проверку и установку зависимостей
- ✅ Сбор конфигурации (email, Telegram)
- ✅ Создание .env файла
- ✅ Настройку UFW firewall
- ✅ Установку Fail2Ban (опционально)
- ✅ Запуск Docker контейнеров
- ✅ Тест Telegram уведомлений

### 7.3 Добавление первого сервиса

```bash
# Пример: добавление FastAPI бэкенда
cd /opt/balancer
sudo bash scripts/add-service.sh

# Ввести:
# Имя: myapi
# Поддомен: api
# Домен: example.ru
# Тип: 1 (FastAPI)
# Хост: fastapi-container
# Порт: 8000
```

### 7.4 Проверка работы

```bash
# Проверка статуса контейнеров
docker compose ps

# Проверка логов
docker compose logs -f nginx

# Проверка сертификатов
sudo ls -la /opt/balancer/certbot/conf/live/

# Тест доступности
curl -I https://api.example.ru
```

---

## 8. Эксплуатация

### 8.1 Управление системой

```bash
# Статус сервиса
sudo systemctl status balancer

# Перезапуск
sudo systemctl restart balancer

# Просмотр логов
sudo docker compose -f /opt/balancer/docker-compose.yml logs -f

# Перезагрузка Nginx без downtime
sudo docker exec nginx-proxy nginx -s reload
```

### 8.2 Работа с сервисами

#### Добавление сервиса
```bash
sudo bash /opt/balancer/scripts/add-service.sh
```

#### Удаление сервиса
```bash
sudo bash /opt/balancer/scripts/remove-service.sh
```

#### Проверка конфигурации
```bash
sudo docker exec nginx-proxy nginx -t
```

### 8.3 Работа с SSL сертификатами

#### Ручное обновление
```bash
# Обновить все сертификаты
sudo docker compose -f /opt/balancer/docker-compose.yml run --rm certbot renew

# Обновить конкретный домен
sudo docker compose -f /opt/balancer/docker-compose.yml run --rm certbot \
    renew --cert-name api.example.ru
```

#### Проверка сертификата
```bash
sudo openssl x509 -in /opt/balancer/certbot/conf/live/api.example.ru/fullchain.pem -text -noout
```

### 8.4 Мониторинг логов

```bash
# Общий access лог
sudo tail -f /opt/balancer/logs/nginx/access.log

# Логи ошибок
sudo tail -f /opt/balancer/logs/nginx/error.log

# Логи конкретного сервиса
sudo tail -f /opt/balancer/logs/nginx/myapi-access.log

# Health check лог
sudo tail -f /opt/balancer/logs/health-check.log

# Stream (TCP) логи
sudo tail -f /opt/balancer/logs/nginx/stream-access.log
```

### 8.5 Анализ логов

```bash
# Топ IP адресов
awk '{print $1}' /opt/balancer/logs/nginx/access.log | sort | uniq -c | sort -nr | head -20

# Топ URL
awk '{print $7}' /opt/balancer/logs/nginx/access.log | sort | uniq -c | sort -nr | head -20

# Статистика HTTP кодов
awk '{print $9}' /opt/balancer/logs/nginx/access.log | sort | uniq -c | sort -nr

# Среднее время ответа
awk '{if($NF ~ /rt=/) {split($NF,a,"="); sum+=a[2]; count++}} END {print sum/count}' \
    /opt/balancer/logs/nginx/access.log
```

### 8.6 Настройка IP-фильтрации

#### Для HTTP/HTTPS сервиса
```bash
# Отредактировать конфиг сервиса
sudo vim /opt/balancer/nginx/conf.d/myservice.conf

# Раскомментировать и настроить
# allow 192.168.1.0/24;
# allow 10.0.0.0/8;
# deny all;

# Перезагрузить Nginx
sudo docker exec nginx-proxy nginx -t && sudo docker exec nginx-proxy nginx -s reload
```

#### Для TCP сервиса (через UFW)
```bash
# Удалить общее правило
sudo ufw delete allow 5432/tcp

# Добавить ограничение по IP
sudo ufw allow from 192.168.1.0/24 to any port 5432 proto tcp comment 'PostgreSQL'

# Проверить
sudo ufw status numbered
```

---

## 9. Troubleshooting

### 9.1 Частые проблемы и решения

#### Проблема: "502 Bad Gateway"

**Причины:**
1. Backend сервис не запущен
2. Неверное имя хоста в конфиге
3. Backend не в той же Docker сети

**Решение:**
```bash
# 1. Проверить backend
docker ps | grep backend-name
docker logs backend-name

# 2. Проверить сетевую связность
docker exec nginx-proxy ping backend-name

# 3. Проверить конфиг
grep upstream /opt/balancer/nginx/conf.d/service.conf

# 4. Проверить Docker сеть
docker network inspect proxy_network
```

#### Проблема: SSL сертификат не получается

**Причины:**
1. DNS запись не настроена
2. Порт 80 закрыт
3. Неверный email

**Решение:**
```bash
# 1. Проверить DNS
host api.example.ru

# 2. Проверить UFW
sudo ufw status | grep 80

# 3. Попробовать вручную с debug
sudo docker compose run --rm certbot certonly \
    --webroot -w /var/www/certbot \
    -d api.example.ru \
    --dry-run \
    --verbose

# 4. Проверить ACME challenge
curl http://api.example.ru/.well-known/acme-challenge/test
```

#### Проблема: High CPU/Memory usage

**Решение:**
```bash
# 1. Проверить процессы
docker stats

# 2. Проверить nginx worker processes
docker exec nginx-proxy ps aux | grep nginx

# 3. Проверить количество соединений
docker exec nginx-proxy netstat -an | grep ESTABLISHED | wc -l

# 4. Проверить логи на аномалии
sudo tail -1000 /opt/balancer/logs/nginx/access.log | \
    awk '{print $1}' | sort | uniq -c | sort -nr | head -10
```

#### Проблема: Контейнеры не запускаются

**Решение:**
```bash
# 1. Проверить логи
docker compose -f /opt/balancer/docker-compose.yml logs

# 2. Проверить порты
sudo netstat -tulpn | grep -E '80|443|5432|5984'

# 3. Пересоздать контейнеры
cd /opt/balancer
docker compose down
docker compose up -d

# 4. Проверить volumes
docker volume ls | grep balancer
```

### 9.2 Диагностические команды

```bash
# Общая проверка системы
sudo bash /opt/balancer/scripts/health-check.sh

# Проверка конфигурации Nginx
sudo docker exec nginx-proxy nginx -t

# Проверка upstream серверов
sudo docker exec nginx-proxy nginx -T | grep upstream -A 3

# Проверка SSL сертификатов
sudo docker compose run --rm certbot certificates

# Проверка Docker сетей
docker network ls
docker network inspect proxy_network

# Проверка UFW
sudo ufw status verbose

# Проверка Fail2Ban
sudo fail2ban-client status
```

### 9.3 Восстановление после сбоя

```bash
# 1. Остановить все
cd /opt/balancer
sudo docker compose down

# 2. Проверить и очистить
docker system prune -f

# 3. Проверить конфигурацию
find nginx/conf.d -name "*.conf" -exec nginx -t -c {} \;

# 4. Запустить заново
sudo docker compose up -d

# 5. Проверить логи
docker compose logs -f
```

---

## 10. Приложения

### 10.1 Пример .env файла

```bash
# /opt/balancer/.env

# Let's Encrypt
LETSENCRYPT_EMAIL=admin@example.ru

# Telegram Alerts
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
TELEGRAM_CHAT_ID=-1001234567890

# System
TZ=Europe/Moscow

# Docker Compose
COMPOSE_PROJECT_NAME=balancer
```

### 10.2 Примеры docker-compose для сервисов

#### FastAPI Backend

```yaml
# Пример docker-compose.yml для FastAPI приложения

version: '3.8'

services:
  fastapi:
    build: .
    container_name: fastapi-app
    restart: unless-stopped
    environment:
      - DATABASE_URL=postgresql://user:pass@postgres:5432/db
    networks:
      - proxy_network
      - internal_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 3s
      retries: 3
    labels:
      - "com.balancer.enable=true"

networks:
  proxy_network:
    external: true
  internal_network:
    external: true
```

#### Frontend (Nginx Static)

```yaml
# Пример docker-compose.yml для фронтенда

version: '3.8'

services:
  frontend:
    image: nginx:alpine
    container_name: frontend-app
    restart: unless-stopped
    volumes:
      - ./dist:/usr/share/nginx/html:ro
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - proxy_network
    labels:
      - "com.balancer.enable=true"

networks:
  proxy_network:
    external: true
```

#### PostgreSQL

```yaml
# Пример docker-compose.yml для PostgreSQL

version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: postgres-db
    restart: unless-stopped
    environment:
      - POSTGRES_USER=myuser
      - POSTGRES_PASSWORD=mypassword
      - POSTGRES_DB=mydb
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - internal_network
    labels:
      - "com.balancer.enable=true"

volumes:
  postgres_data:

networks:
  internal_network:
    external: true
```

#### CouchDB

```yaml
# Пример docker-compose.yml для CouchDB

version: '3.8'

services:
  couchdb:
    image: couchdb:3
    container_name: couchdb-db
    restart: unless-stopped
    environment:
      - COUCHDB_USER=admin
      - COUCHDB_PASSWORD=password
    volumes:
      - couchdb_data:/opt/couchdb/data
    networks:
      - internal_network
    labels:
      - "com.balancer.enable=true"

volumes:
  couchdb_data:

networks:
  internal_network:
    external: true
```

### 10.3 Полезные команды

```bash
# ═══ Управление Balancer ═══

# Статус
systemctl status balancer

# Запуск
systemctl start balancer

# Остановка
systemctl stop balancer

# Перезапуск
systemctl restart balancer

# Логи systemd
journalctl -u balancer -f

# ═══ Docker Compose ═══

# Запуск
docker compose -f /opt/balancer/docker-compose.yml up -d

# Остановка
docker compose -f /opt/balancer/docker-compose.yml down

# Перезапуск конкретного сервиса
docker compose -f /opt/balancer/docker-compose.yml restart nginx

# Просмотр логов
docker compose -f /opt/balancer/docker-compose.yml logs -f

# Пересборка образов
docker compose -f /opt/balancer/docker-compose.yml build --no-cache

# ═══ Nginx ═══

# Проверка конфигурации
docker exec nginx-proxy nginx -t

# Перезагрузка без downtime
docker exec nginx-proxy nginx -s reload

# Полная конфигурация
docker exec nginx-proxy nginx -T

# Статистика
docker exec nginx-proxy nginx -V

# ═══ Certbot ═══

# Список сертификатов
docker compose run --rm certbot certificates

# Обновление всех
docker compose run --rm certbot renew

# Обновление конкретного
docker compose run --rm certbot renew --cert-name api.example.ru

# Удаление сертификата
docker compose run --rm certbot delete --cert-name api.example.ru

# ═══ Логи ═══

# Real-time мониторинг access log
tail -f /opt/balancer/logs/nginx/access.log | grep -v "health"

# Только ошибки
tail -f /opt/balancer/logs/nginx/error.log

# Статистика за последний час
awk -v d="$(date -d '1 hour ago' '+%d/%b/%Y:%H:%M:%S')" \
    '$4 > "["d {print}' /opt/balancer/logs/nginx/access.log | \
    awk '{print $9}' | sort | uniq -c

# ═══ UFW ═══

# Статус с номерами
ufw status numbered

# Добавить правило
ufw allow from 192.168.1.0/24 to any port 5432 proto tcp

# Удалить правило
ufw delete <номер>

# Перезагрузка
ufw reload

# ═══ Fail2Ban ═══

# Статус
fail2ban-client status

# Статус конкретной jail
fail2ban-client status nginx-http-auth

# Разблокировать IP
fail2ban-client set nginx-http-auth unbanip <IP>

# ═══ Мониторинг ═══

# Использование ресурсов
docker stats

# Проверка портов
netstat -tulpn | grep -E '80|443|5432|5984'

# Проверка соединений
netstat -an | grep ESTABLISHED | wc -l

# Место на диске
df -h

# Размер логов
du -sh /opt/balancer/logs/*
```

### 10.4 Чек-лист запуска

```
☐ 1. Подготовка сервера
   ☐ Обновление ОС
   ☐ Установка Docker и Docker Compose
   ☐ Настройка UFW
   ☐ Настройка Fail2Ban (опционально)

☐ 2. Установка Balancer
   ☐ Создание структуры /opt/balancer
   ☐ Копирование файлов конфигурации
   ☐ Запуск init-balancer.sh
   ☐ Проверка создания .env файла

☐ 3. Настройка DNS
   ☐ Создание A записи для основного домена
   ☐ Создание A/CNAME записей для поддоменов
   ☐ Проверка DNS резолвинга

☐ 4. Запуск сервисов
   ☐ Запуск Docker контейнеров
   ☐ Проверка статуса контейнеров
   ☐ Проверка логов на ошибки

☐ 5. Добавление сервисов
   ☐ Добавление первого сервиса (add-service.sh)
   ☐ Проверка получения SSL сертификата
   ☐ Тест доступности через HTTPS

☐ 6. Проверка безопасности
   ☐ Настройка IP-фильтрации для БД
   ☐ Проверка UFW правил
   ☐ Тест Fail2Ban

☐ 7. Мониторинг
   ☐ Проверка работы health checks
   ☐ Тест Telegram уведомлений
   ☐ Настройка алертов

☐ 8. Документация
   ☐ Сохранение всех паролей
   ☐ Документирование конфигурации
   ☐ Создание runbook для команды
```

### 10.5 Контакты и поддержка

**Документация:**
- Nginx: https://nginx.org/ru/docs/
- Let's Encrypt: https://letsencrypt.org/docs/
- Docker: https://docs.docker.com/
- UFW: https://help.ubuntu.com/community/UFW

**Сообщество:**
- Nginx Forum: https://forum.nginx.org/
- Docker Community: https://forums.docker.com/
- Stack Overflow: тег [nginx], [docker], [lets-encrypt]

---

## Глоссарий

| Термин | Описание |
|--------|----------|
| **Reverse Proxy** | Сервер, принимающий запросы от клиентов и пересылающий их на backend серверы |
| **SSL/TLS Termination** | Расшифровка SSL/TLS трафика на уровне прокси |
| **Let's Encrypt** | Бесплатный автоматизированный центр сертификации |
| **Certbot** | Клиент для автоматизации получения Let's Encrypt сертификатов |
| **ACME Protocol** | Протокол для автоматической валидации домена и выдачи сертификатов |
| **Upstream** | Backend сервер, на который Nginx проксирует запросы |
| **Health Check** | Проверка работоспособности backend сервиса |
| **Graceful Reload** | Перезагрузка конфигурации без разрыва активных соединений |
| **Rate Limiting** | Ограничение количества запросов с одного IP |
| **Stream Module** | Модуль Nginx для проксирования TCP/UDP трафика |
| **UFW** | Uncomplicated Firewall - простой интерфейс для iptables |
| **Fail2Ban** | Система защиты от brute-force атак |

---

**Конец документа**

---

**Информация о документе:**
- **Версия:** 2.0 FINAL
- **Дата:** 06.11.2025
- **Проект:** Balancer
- **Технология:** Nginx + Docker + Let's Encrypt
- **Статус:** Готов к имплементации

-e 

---


# Дополнение к ПРД: Архитектура прямого подключения фронтендов

## Версия: 2.1 - Frontend Direct Mount Extension
**Дата:** 06.11.2025  
**Статус:** Дополнение к основному ПРД

---

## Содержание дополнения

1. [Обзор архитектуры подключения](#1-обзор-архитектуры-подключения)
2. [Обновленная структура каталогов](#2-обновленная-структура-каталогов)
3. [Типы подключения сервисов](#3-типы-подключения-сервисов)
4. [Конфигурации для direct mount](#4-конфигурации-для-direct-mount)
5. [Обновленный скрипт добавления](#5-обновленный-скрипт-добавления)
6. [Обновленный Docker Compose](#6-обновленный-docker-compose)
7. [Workflow развертывания](#7-workflow-развертывания)

---

## 1. Обзор архитектуры подключения

### 1.1 Проблема дублирования

**Текущая проблема:**
```
Client -> Nginx-Proxy -> Frontend-Nginx-Container -> Static Files
          (80MB RAM)      (80MB RAM)
```

**Оптимизированное решение:**
```
Client -> Nginx-Proxy -> Static Files (Direct Mount)
          (80MB RAM)
```

### 1.2 Типы подключения сервисов

```mermaid
graph TB
    subgraph "Тип 1: Proxy (Backend Services)"
        C1[Client] --> NP1[Nginx Proxy]
        NP1 --> BC1[Backend Container<br/>FastAPI/API]
        style BC1 fill:#FF9800
    end
    
    subgraph "Тип 2: Direct Static (Frontend)"
        C2[Client] --> NP2[Nginx Proxy]
        NP2 --> VM[Volume Mount<br/>/static/frontend1]
        style VM fill:#4CAF50
    end
    
    subgraph "Тип 3: Proxy Frontend Container"
        C3[Client] --> NP3[Nginx Proxy]
        NP3 --> FC[Frontend Container<br/>Nginx]
        FC --> FS[Static Files]
        style FC fill:#2196F3
    end
    
    subgraph "Тип 4: TCP Stream (Database)"
        C4[Client] --> NP4[Nginx Proxy<br/>TCP Stream]
        NP4 --> DB[(Database<br/>PostgreSQL/CouchDB)]
        style DB fill:#9C27B0
    end
    
    style NP1 fill:#F44336,color:#fff
    style NP2 fill:#F44336,color:#fff
    style NP3 fill:#F44336,color:#fff
    style NP4 fill:#F44336,color:#fff
```

### 1.3 Сравнение подходов

| Критерий | Proxy Container | Direct Static Mount |
|----------|----------------|---------------------|
| **Производительность** | Среднее (2 прокси) | Высокое (1 прокси) |
| **Потребление RAM** | ~160MB | ~80MB |
| **Сложность деплоя** | Средняя | Низкая |
| **Обновление контента** | Restart container | Copy files |
| **Изоляция** | Высокая | Средняя |
| **Hot reload** | Нет | Да (nginx reload) |
| **Рекомендация** | Для SSR, сложных SPA | Для статики, билдов |

---

## 2. Обновленная структура каталогов

```
/opt/balancer/
├── docker-compose.yml
├── .env
├── README.md
│
├── nginx/
│   ├── nginx.conf
│   ├── conf.d/
│   │   ├── default.conf
│   │   ├── streams.conf
│   │   ├── proxy/                    # NEW: Proxy конфиги
│   │   │   ├── api-service.conf
│   │   │   └── backend-service.conf
│   │   ├── static/                   # NEW: Static конфиги
│   │   │   ├── frontend1.conf
│   │   │   └── frontend2.conf
│   │   └── external/                 # NEW: External proxy конфиги
│   │       └── admin-frontend.conf
│   ├── snippets/
│   │   ├── ssl-params.conf
│   │   ├── security-headers.conf
│   │   ├── proxy-params.conf
│   │   └── static-params.conf       # NEW: Параметры для статики
│   └── html/
│       ├── 50x.html
│       └── index.html
│
├── static/                           # NEW: Статический контент
│   ├── frontend1/                    # Прямое подключение
│   │   ├── index.html
│   │   ├── assets/
│   │   └── .version                  # Версия деплоя
│   ├── frontend2/
│   │   ├── index.html
│   │   └── assets/
│   └── shared/                       # Общие ресурсы
│       ├── images/
│       └── fonts/
│
├── certbot/
│   └── conf/
│
├── logs/
│   ├── nginx/
│   │   ├── proxy/                    # NEW: Логи proxy сервисов
│   │   ├── static/                   # NEW: Логи static сервисов
│   │   └── external/                 # NEW: Логи external сервисов
│   └── certbot/
│
├── scripts/
│   ├── init-balancer.sh
│   ├── add-service.sh               # UPDATED: Расширенный функционал
│   ├── remove-service.sh
│   ├── deploy-frontend.sh           # NEW: Деплой статики
│   ├── health-check.sh
│   └── telegram-alert.sh
│
├── templates/
│   ├── service-fastapi.conf.tmpl
│   ├── service-frontend-proxy.conf.tmpl
│   ├── service-frontend-static.conf.tmpl  # NEW: Прямая статика
│   ├── service-http.conf.tmpl
│   └── service-tcp.conf.tmpl
│
├── deployments/                      # NEW: История деплоев
│   ├── frontend1/
│   │   ├── 2025-11-06_10-30-15/
│   │   └── current -> 2025-11-06_10-30-15
│   └── frontend2/
│
└── healthcheck/
    ├── Dockerfile
    └── entrypoint.sh
```

---

## 3. Типы подключения сервисов

### 3.1 Классификация

```mermaid
flowchart TD
    Start([Добавление сервиса]) --> Type{Тип сервиса?}
    
    Type -->|Backend API| ProxyBackend[Proxy Backend]
    ProxyBackend --> ProxyConf[Создать конфиг в<br/>conf.d/proxy/]
    ProxyConf --> SSL1[Получить SSL]
    
    Type -->|Frontend Static| SubType{Подтип<br/>Frontend?}
    
    SubType -->|Direct Mount| DirectStatic[Direct Static Mount]
    DirectStatic --> CreateDir[Создать /static/name/]
    CreateDir --> StaticConf[Создать конфиг в<br/>conf.d/static/]
    StaticConf --> SSL2[Получить SSL]
    
    SubType -->|SSR/Complex| ProxyFrontend[Proxy Frontend Container]
    ProxyFrontend --> ExternalConf[Создать конфиг в<br/>conf.d/external/]
    ExternalConf --> SSL3[Получить SSL]
    
    Type -->|Database TCP| StreamConf[Добавить в streams.conf]
    StreamConf --> UFWRule[Настроить UFW]
    
    SSL1 --> Reload[nginx -s reload]
    SSL2 --> Reload
    SSL3 --> Reload
    UFWRule --> Reload
    
    Reload --> Success([Готово])
    
    style Start fill:#4CAF50,stroke:#388E3C,color:#fff
    style Success fill:#4CAF50,stroke:#388E3C,color:#fff
    style ProxyBackend fill:#FF9800,stroke:#F57C00,color:#fff
    style DirectStatic fill:#2196F3,stroke:#1976D2,color:#fff
    style ProxyFrontend fill:#9C27B0,stroke:#7B1FA2,color:#fff
    style StreamConf fill:#F44336,stroke:#D32F2F,color:#fff
```

### 3.2 Когда использовать каждый тип

| Тип | Использовать когда | Примеры |
|-----|-------------------|---------|
| **Proxy Backend** | API, динамический контент | FastAPI, Django REST, Node.js API |
| **Direct Static** | Статический билд, SPA | React build, Vue build, Angular dist |
| **Proxy Frontend Container** | SSR, сложная логика, кастомный nginx | Next.js, Nuxt.js, custom nginx configs |
| **TCP Stream** | Базы данных | PostgreSQL, MySQL, MongoDB, CouchDB |

---

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

## 5. Обновленный скрипт добавления

```bash
#!/bin/bash
# /opt/balancer/scripts/add-service.sh
# UPDATED VERSION 2.1 - С поддержкой разных типов подключения

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NGINX_CONF_DIR="$PROJECT_DIR/nginx/conf.d"
TEMPLATES_DIR="$PROJECT_DIR/templates"
STATIC_DIR="$PROJECT_DIR/static"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Добавление нового сервиса          ║${NC}"
echo -e "${BLUE}║     Version 2.1 - Extended             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"

# Загрузка переменных окружения
if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    echo -e "${RED}Ошибка: .env файл не найден${NC}"
    exit 1
fi

# Функции валидации (как в предыдущей версии)
validate_domain() {
    local domain=$1
    if [[ ! $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        echo -e "${RED}Ошибка: Некорректный формат домена${NC}"
        return 1
    fi
    return 0
}

check_dns() {
    local domain=$1
    echo -e "${YELLOW}Проверка DNS записи для $domain...${NC}"
    
    if host $domain > /dev/null 2>&1; then
        local ip=$(host $domain | awk '/has address/ { print $4 }' | head -1)
        local server_ip=$(curl -s ifconfig.me || curl -s icanhazip.com)
        
        echo "DNS указывает на: $ip"
        echo "IP сервера: $server_ip"
        
        if [ "$ip" == "$server_ip" ]; then
            echo -e "${GREEN}✓ DNS запись корректна${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ DNS и IP сервера не совпадают${NC}"
            read -p "Продолжить? (y/n): " confirm
            [ "$confirm" != "y" ] && return 1
        fi
    else
        echo -e "${YELLOW}⚠ DNS запись не найдена${NC}"
        read -p "Продолжить без DNS? (y/n): " confirm
        [ "$confirm" != "y" ] && return 1
    fi
    return 0
}

# === НОВАЯ ФУНКЦИЯ: Выбор типа сервиса ===
select_service_category() {
    echo -e "\n${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Категория сервиса                  ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}\n"
    
    echo -e "${YELLOW}Выберите категорию сервиса:${NC}"
    echo ""
    echo "  ${GREEN}1) Backend API${NC}"
    echo "     └─ FastAPI, Django, Node.js, другие API"
    echo ""
    echo "  ${GREEN}2) Frontend (Static)${NC}"
    echo "     └─ React, Vue, Angular билды (рекомендуется)"
    echo ""
    echo "  ${GREEN}3) Frontend (Container)${NC}"
    echo "     └─ SSR приложения, кастомный Nginx"
    echo ""
    echo "  ${GREEN}4) Database (TCP Stream)${NC}"
    echo "     └─ PostgreSQL, MySQL, CouchDB"
    echo ""
    
    read -p "Ваш выбор (1-4): " CATEGORY
    
    case $CATEGORY in
        1) CATEGORY_TYPE="backend";;
        2) CATEGORY_TYPE="frontend-static";;
        3) CATEGORY_TYPE="frontend-proxy";;
        4) CATEGORY_TYPE="database";;
        *) echo -e "${RED}Некорректный выбор${NC}"; return 1;;
    esac
    
    echo -e "${GREEN}✓ Выбрана категория: $CATEGORY_TYPE${NC}"
    return 0
}

# === НОВАЯ ФУНКЦИЯ: Конфигурация Backend ===
configure_backend_service() {
    echo -e "\n${CYAN}═══ Backend API конфигурация ═══${NC}\n"
    
    echo -e "${YELLOW}Тип Backend API:${NC}"
    echo "1. FastAPI"
    echo "2. Django / Flask"
    echo "3. Node.js / Express"
    echo "4. Other HTTP API"
    read -p "Выбор (1-4): " backend_type
    
    case $backend_type in
        1) SERVICE_TEMPLATE="service-fastapi.conf.tmpl";;
        2|3|4) SERVICE_TEMPLATE="service-http.conf.tmpl";;
        *) SERVICE_TEMPLATE="service-http.conf.tmpl";;
    esac
    
    read -p "Имя Docker контейнера бэкенда: " BACKEND_HOST
    read -p "Порт бэкенда: " BACKEND_PORT
    
    read -p "Включить IP-фильтрацию? (y/n): " IP_FILTER
    if [ "$IP_FILTER" == "y" ]; then
        read -p "Разрешенная подсеть (например: 192.168.1.0/24): " ALLOWED_SUBNET
    fi
    
    CONFIG_SUBDIR="proxy"
}

# === НОВАЯ ФУНКЦИЯ: Конфигурация Frontend Static ===
configure_frontend_static() {
    echo -e "\n${CYAN}═══ Frontend Static конфигурация ═══${NC}\n"
    
    echo -e "${GREEN}Этот режим монтирует статические файлы напрямую в Nginx${NC}"
    echo -e "${GREEN}Нет дополнительного контейнера = меньше ресурсов${NC}\n"
    
    SERVICE_TEMPLATE="service-frontend-static.conf.tmpl"
    CONFIG_SUBDIR="static"
    
    # Создание директории для статики
    STATIC_SERVICE_DIR="$STATIC_DIR/$SERVICE_NAME"
    mkdir -p "$STATIC_SERVICE_DIR"
    
    echo -e "${YELLOW}Директория для статики создана:${NC} $STATIC_SERVICE_DIR"
    echo -e "${YELLOW}После настройки скопируйте ваш билд в:${NC}"
    echo -e "  ${CYAN}$STATIC_SERVICE_DIR/${NC}\n"
    
    # Создание placeholder файлов
    cat > "$STATIC_SERVICE_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Service Placeholder</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            text-align: center;
            padding: 2rem;
            background: rgba(0,0,0,0.2);
            border-radius: 10px;
        }
        h1 { margin-bottom: 1rem; }
        .status { color: #4ade80; font-size: 1.2rem; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Service Ready</h1>
        <p class="status">Placeholder page - deploy your application</p>
        <p>Service: <strong id="serviceName"></strong></p>
        <p><small>Replace this index.html with your build</small></p>
    </div>
    <script>
        document.getElementById('serviceName').textContent = window.location.hostname;
    </script>
</body>
</html>
EOF
    
    echo "1.0.0-placeholder" > "$STATIC_SERVICE_DIR/.version"
    
    echo -e "${GREEN}✓ Placeholder файлы созданы${NC}"
    
    BACKEND_HOST=""
    BACKEND_PORT=""
}

# === НОВАЯ ФУНКЦИЯ: Конфигурация Frontend Proxy ===
configure_frontend_proxy() {
    echo -e "\n${CYAN}═══ Frontend Container конфигурация ═══${NC}\n"
    
    echo -e "${YELLOW}Используйте этот режим для:${NC}"
    echo "  - SSR приложений (Next.js, Nuxt.js)"
    echo "  - Сложных конфигураций Nginx"
    echo "  - Когда нужна изоляция в контейнере"
    echo ""
    
    SERVICE_TEMPLATE="service-frontend-proxy.conf.tmpl"
    CONFIG_SUBDIR="external"
    
    read -p "Имя Docker контейнера frontend: " BACKEND_HOST
    read -p "Порт frontend контейнера: " BACKEND_PORT
}

# === НОВАЯ ФУНКЦИЯ: Конфигурация Database ===
configure_database() {
    echo -e "\n${CYAN}═══ Database TCP Stream конфигурация ═══${NC}\n"
    
    echo -e "${YELLOW}Тип базы данных:${NC}"
    echo "1. PostgreSQL (5432)"
    echo "2. MySQL/MariaDB (3306)"
    echo "3. CouchDB (5984)"
    echo "4. MongoDB (27017)"
    echo "5. Other"
    read -p "Выбор (1-5): " db_type
    
    case $db_type in
        1) DEFAULT_PORT=5432; DB_NAME="PostgreSQL";;
        2) DEFAULT_PORT=3306; DB_NAME="MySQL";;
        3) DEFAULT_PORT=5984; DB_NAME="CouchDB";;
        4) DEFAULT_PORT=27017; DB_NAME="MongoDB";;
        5) DEFAULT_PORT=""; DB_NAME="Custom";;
    esac
    
    read -p "Имя Docker контейнера БД: " BACKEND_HOST
    
    if [ -n "$DEFAULT_PORT" ]; then
        read -p "Порт БД [$DEFAULT_PORT]: " BACKEND_PORT
        BACKEND_PORT=${BACKEND_PORT:-$DEFAULT_PORT}
    else
        read -p "Порт БД: " BACKEND_PORT
    fi
    
    read -p "Внешний TCP порт [$BACKEND_PORT]: " EXTERNAL_PORT
    EXTERNAL_PORT=${EXTERNAL_PORT:-$BACKEND_PORT}
    
    echo -e "\n${YELLOW}⚠ ВАЖНО: Безопасность${NC}"
    echo "Рекомендуется ограничить доступ по IP"
    read -p "Настроить IP-фильтрацию через UFW? (y/n): " SETUP_UFW
    
    if [ "$SETUP_UFW" == "y" ]; then
        read -p "Разрешенная подсеть (например: 192.168.1.0/24): " ALLOWED_SUBNET
    fi
    
    CONFIG_SUBDIR=""
}

# === ОСНОВНОЙ ПРОЦЕСС ===

# Сбор базовой информации
echo -e "${BLUE}═══ Базовые параметры ═══${NC}\n"

read -p "Имя сервиса (латиница, без пробелов): " SERVICE_NAME
SERVICE_NAME=$(echo "$SERVICE_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_-')

read -p "Поддомен (например: api): " SUBDOMAIN
read -p "Основной домен (например: example.ru): " MAIN_DOMAIN
DOMAIN="${SUBDOMAIN}.${MAIN_DOMAIN}"

validate_domain "$DOMAIN" || exit 1

# Выбор категории
select_service_category || exit 1

# Конфигурация в зависимости от категории
case $CATEGORY_TYPE in
    "backend")
        configure_backend_service
        ;;
    "frontend-static")
        configure_frontend_static
        ;;
    "frontend-proxy")
        configure_frontend_proxy
        ;;
    "database")
        configure_database
        ;;
esac

# Проверка DNS (кроме database)
if [ "$CATEGORY_TYPE" != "database" ]; then
    check_dns "$DOMAIN" || exit 1
fi

# === ПОДТВЕРЖДЕНИЕ ===
echo -e "\n${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Подтверждение конфигурации         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"

echo "Имя сервиса: ${GREEN}$SERVICE_NAME${NC}"
echo "Категория: ${GREEN}$CATEGORY_TYPE${NC}"
echo "Домен: ${GREEN}$DOMAIN${NC}"

if [ "$CATEGORY_TYPE" != "frontend-static" ] && [ "$CATEGORY_TYPE" != "database" ]; then
    echo "Бэкенд: ${GREEN}$BACKEND_HOST:$BACKEND_PORT${NC}"
fi

if [ "$CATEGORY_TYPE" == "frontend-static" ]; then
    echo "Статика: ${GREEN}$STATIC_SERVICE_DIR${NC}"
fi

if [ "$CATEGORY_TYPE" == "database" ]; then
    echo "Бэкенд: ${GREEN}$BACKEND_HOST:$BACKEND_PORT${NC}"
    echo "Внешний порт: ${GREEN}$EXTERNAL_PORT${NC}"
fi

if [ -n "$CONFIG_SUBDIR" ]; then
    echo "Конфиг: ${GREEN}conf.d/$CONFIG_SUBDIR/$SERVICE_NAME.conf${NC}"
else
    echo "Конфиг: ${GREEN}conf.d/streams.conf${NC}"
fi

echo ""
read -p "Подтвердите создание (yes/no): " CONFIRM
[ "$CONFIRM" != "yes" ] && { echo -e "${RED}Отменено${NC}"; exit 0; }

# === СОЗДАНИЕ КОНФИГУРАЦИИ ===
echo -e "\n${YELLOW}Создание конфигурации...${NC}"

if [ "$CATEGORY_TYPE" != "database" ]; then
    # HTTP/HTTPS конфигурация
    
    # Создание поддиректории если нужно
    if [ -n "$CONFIG_SUBDIR" ]; then
        mkdir -p "$NGINX_CONF_DIR/$CONFIG_SUBDIR"
        CONFIG_FILE="$NGINX_CONF_DIR/$CONFIG_SUBDIR/${SERVICE_NAME}.conf"
        
        # Создать поддиректорию для логов
        mkdir -p "$PROJECT_DIR/logs/nginx/$CONFIG_SUBDIR"
    else
        CONFIG_FILE="$NGINX_CONF_DIR/${SERVICE_NAME}.conf"
    fi
    
    # Генерация конфига
    sed -e "s/{SERVICE_NAME}/$SERVICE_NAME/g" \
        -e "s/{DOMAIN}/$DOMAIN/g" \
        -e "s/{BACKEND_HOST}/$BACKEND_HOST/g" \
        -e "s/{BACKEND_PORT}/$BACKEND_PORT/g" \
        "$TEMPLATES_DIR/$SERVICE_TEMPLATE" > "$CONFIG_FILE"
    
    # IP-фильтрация для backend
    if [ "$IP_FILTER" == "y" ] && [ -n "$ALLOWED_SUBNET" ]; then
        sed -i "/# IP фильтрация/a\    allow $ALLOWED_SUBNET;\n    deny all;" "$CONFIG_FILE"
    fi
    
    echo -e "${GREEN}✓ Конфиг создан: $CONFIG_FILE${NC}"
    
    # Получение SSL сертификата
    echo -e "\n${YELLOW}Получение SSL сертификата...${NC}"
    
    docker compose -f "$PROJECT_DIR/docker-compose.yml" run --rm certbot \
        certonly --webroot -w /var/www/certbot \
        --email "$LETSENCRYPT_EMAIL" \
        --agree-tos \
        --no-eff-email \
        -d "$DOMAIN" \
        --non-interactive || {
            echo -e "${RED}✗ Ошибка получения SSL${NC}"
            rm "$CONFIG_FILE"
            exit 1
        }
    
    echo -e "${GREEN}✓ SSL сертификат получен${NC}"
    
else
    # TCP Stream конфигурация
    STREAM_CONF="$NGINX_CONF_DIR/streams.conf"
    
    cat >> "$STREAM_CONF" << EOF

# $SERVICE_NAME - $DB_NAME
upstream ${SERVICE_NAME}_backend {
    server ${BACKEND_HOST}:${BACKEND_PORT} max_fails=3 fail_timeout=30s;
}

server {
    listen ${EXTERNAL_PORT};
    listen [::]:${EXTERNAL_PORT};
    proxy_pass ${SERVICE_NAME}_backend;
    proxy_connect_timeout 10s;
    proxy_timeout 30m;
}
EOF
    
    echo -e "${GREEN}✓ TCP stream добавлен${NC}"
    
    # Настройка UFW для TCP
    if [ "$SETUP_UFW" == "y" ]; then
        echo -e "${YELLOW}Настройка UFW...${NC}"
        
        # Удалить общее правило если есть
        ufw delete allow "$EXTERNAL_PORT/tcp" 2>/dev/null || true
        
        # Добавить ограниченное правило
        ufw allow from "$ALLOWED_SUBNET" to any port "$EXTERNAL_PORT" proto tcp comment "$SERVICE_NAME"
        ufw reload
        
        echo -e "${GREEN}✓ UFW правило добавлено${NC}"
    else
        echo -e "${YELLOW}⚠ Не забудьте открыть порт $EXTERNAL_PORT в UFW и docker-compose.yml${NC}"
    fi
fi

# === ПРОВЕРКА И ПЕРЕЗАГРУЗКА ===
echo -e "\n${YELLOW}Проверка конфигурации Nginx...${NC}"
docker exec nginx-proxy nginx -t || {
    echo -e "${RED}✗ Ошибка в конфигурации${NC}"
    [ -f "$CONFIG_FILE" ] && rm "$CONFIG_FILE"
    exit 1
}
echo -e "${GREEN}✓ Конфигурация валидна${NC}"

echo -e "\n${YELLOW}Перезагрузка Nginx...${NC}"
docker exec nginx-proxy nginx -s reload || {
    echo -e "${RED}✗ Ошибка перезагрузки${NC}"
    exit 1
}
echo -e "${GREEN}✓ Nginx перезагружен${NC}"

# === УВЕДОМЛЕНИЕ ===
MESSAGE="✅ Новый сервис добавлен\n\n"
MESSAGE+="Сервис: $SERVICE_NAME\n"
MESSAGE+="Категория: $CATEGORY_TYPE\n"
MESSAGE+="Домен: $DOMAIN"

bash "$SCRIPT_DIR/telegram-alert.sh" "$MESSAGE" 2>/dev/null || true

# === ИТОГОВАЯ ИНФОРМАЦИЯ ===
echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Сервис успешно добавлен!          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"

if [ "$CATEGORY_TYPE" == "frontend-static" ]; then
    echo -e "${CYAN}Следующие шаги для деплоя статики:${NC}\n"
    echo -e "1. Скопируйте ваш билд:"
    echo -e "   ${YELLOW}rsync -av dist/ user@server:$STATIC_SERVICE_DIR/${NC}"
    echo -e ""
    echo -e "2. Или используйте скрипт деплоя:"
    echo -e "   ${YELLOW}bash scripts/deploy-frontend.sh $SERVICE_NAME${NC}"
    echo -e ""
    echo -e "3. Проверьте доступность:"
    echo -e "   ${YELLOW}curl -I https://$DOMAIN${NC}\n"
    
elif [ "$CATEGORY_TYPE" != "database" ]; then
    echo -e "Доступен по адресу: ${GREEN}https://$DOMAIN${NC}"
    echo -e "Проверка: ${YELLOW}curl -I https://$DOMAIN${NC}\n"
else
    echo -e "Доступен по порту: ${GREEN}$EXTERNAL_PORT${NC}"
    echo -e "Проверка: ${YELLOW}telnet $MAIN_DOMAIN $EXTERNAL_PORT${NC}\n"
fi

if [ -n "$CONFIG_SUBDIR" ]; then
    echo -e "Конфиг: ${YELLOW}$NGINX_CONF_DIR/$CONFIG_SUBDIR/$SERVICE_NAME.conf${NC}"
    echo -e "Логи: ${YELLOW}tail -f $PROJECT_DIR/logs/nginx/$CONFIG_SUBDIR/${SERVICE_NAME}-*.log${NC}\n"
else
    echo -e "Логи: ${YELLOW}tail -f $PROJECT_DIR/logs/nginx/stream-*.log${NC}\n"
fi

echo -e "${BLUE}═══════════════════════════════════════${NC}"
```

---

## 6. Обновленный Docker Compose

```yaml
# /opt/balancer/docker-compose.yml
# UPDATED VERSION 2.1 - с поддержкой static mount

version: '3.8'

networks:
  proxy_network:
    name: proxy_network
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
  
  internal_network:
    name: internal_network
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 172.22.0.0/16

volumes:
  certbot_conf:
    name: certbot_conf
    driver: local
  certbot_www:
    name: certbot_www
    driver: local
  nginx_cache:
    name: nginx_cache
    driver: local

services:
  nginx:
    image: nginx:1.25-alpine
    container_name: nginx-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      # Database ports (добавляйте по необходимости)
      - "5432:5432"   # PostgreSQL
      - "5984:5984"   # CouchDB
      # - "3306:3306" # MySQL
      # - "27017:27017" # MongoDB
    volumes:
      # Конфигурации
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/snippets:/etc/nginx/snippets:ro
      - ./nginx/html:/usr/share/nginx/html:ro
      
      # SSL сертификаты
      - certbot_conf:/etc/letsencrypt:ro
      - certbot_www:/var/www/certbot:ro
      
      # Статический контент (NEW)
      - ./static:/usr/share/nginx/static:ro
      
      # Кеш и логи
      - nginx_cache:/var/cache/nginx
      - ./logs/nginx:/var/log/nginx
    networks:
      - proxy_network
      - internal_network
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 5s
    labels:
      - "com.balancer.description=Nginx Reverse Proxy"
      - "com.balancer.version=2.1"

  certbot:
    image: certbot/certbot:latest
    container_name: certbot
    restart: unless-stopped
    volumes:
      - certbot_conf:/etc/letsencrypt
      - certbot_www:/var/www/certbot
      - ./logs/certbot:/var/log/letsencrypt
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew --webroot -w /var/www/certbot --quiet --deploy-hook \"nginx -s reload\"; sleep 12h & wait $${!}; done;'"
    depends_on:
      nginx:
        condition: service_healthy
    networks:
      - proxy_network
    labels:
      - "com.balancer.description=SSL Certificate Manager"

  healthcheck:
    build: 
      context: ./healthcheck
      dockerfile: Dockerfile
    container_name: healthcheck-monitor
    restart: unless-stopped
    volumes:
      - ./scripts:/scripts:ro
      - certbot_conf:/etc/letsencrypt:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./logs:/logs
    environment:
      - TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
      - TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}
      - CHECK_INTERVAL=300
      - TZ=${TZ:-Europe/Moscow}
    networks:
      - proxy_network
    depends_on:
      nginx:
        condition: service_healthy
    labels:
      - "com.balancer.description=Health Monitor"
```

---

## 7. Workflow развертывания

### 7.1 Деплой Frontend Static

```bash
#!/bin/bash
# /opt/balancer/scripts/deploy-frontend.sh
# Скрипт для деплоя статического фронтенда

set -e

SERVICE_NAME=$1
BUILD_PATH=$2

if [ -z "$SERVICE_NAME" ] || [ -z "$BUILD_PATH" ]; then
    echo "Usage: $0 <service-name> <build-path>"
    echo "Example: $0 myapp ./dist"
    exit 1
fi

PROJECT_DIR="/opt/balancer"
STATIC_DIR="$PROJECT_DIR/static/$SERVICE_NAME"
DEPLOY_DIR="$PROJECT_DIR/deployments/$SERVICE_NAME"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="$DEPLOY_DIR/$TIMESTAMP"

echo "=== Frontend Deployment ==="
echo "Service: $SERVICE_NAME"
echo "Source: $BUILD_PATH"
echo "Target: $STATIC_DIR"

# Создание backup текущей версии
if [ -d "$STATIC_DIR" ]; then
    echo "Creating backup..."
    mkdir -p "$BACKUP_DIR"
    cp -r "$STATIC_DIR"/* "$BACKUP_DIR/"
    echo "✓ Backup created: $BACKUP_DIR"
fi

# Деплой новой версии
echo "Deploying new version..."
rsync -av --delete "$BUILD_PATH/" "$STATIC_DIR/"

# Создание .version файла
VERSION=$(git describe --tags --always 2>/dev/null || echo "$TIMESTAMP")
echo "$VERSION" > "$STATIC_DIR/.version"

echo "✓ Deployed version: $VERSION"

# Создание symlink на текущую версию
ln -sfn "$BACKUP_DIR" "$DEPLOY_DIR/current"

# Проверка Nginx конфигурации
echo "Testing Nginx configuration..."
docker exec nginx-proxy nginx -t

# Reload Nginx
echo "Reloading Nginx..."
docker exec nginx-proxy nginx -s reload

echo ""
echo "=== Deployment Complete ==="
echo "Version: $VERSION"
echo "Timestamp: $TIMESTAMP"
echo "Backup: $BACKUP_DIR"

# Очистка старых бэкапов (старше 7 дней)
find "$DEPLOY_DIR" -maxdepth 1 -type d -mtime +7 ! -name "current" -exec rm -rf {} \; 2>/dev/null || true

# Отправка уведомления
bash "$PROJECT_DIR/scripts/telegram-alert.sh" \
    "🚀 Frontend deployed\n\nService: $SERVICE_NAME\nVersion: $VERSION\nTime: $TIMESTAMP" \
    2>/dev/null || true

echo ""
echo "Test: curl -I https://<your-domain>"
```

### 7.2 Процесс разработки и деплоя

```mermaid
sequenceDiagram
    participant D as Developer
    participant B as Build System
    participant S as Server
    participant N as Nginx
    participant U as Users
    
    D->>D: Разработка фронтенда
    D->>B: git push / CI trigger
    B->>B: npm run build
    B->>B: Создание dist/
    
    alt Автоматический деплой
        B->>S: rsync dist/ → /opt/balancer/static/app/
    else Ручной деплой
        D->>S: bash deploy-frontend.sh app ./dist
    end
    
    S->>S: Backup текущей версии
    S->>S: Копирование новых файлов
    S->>S: Создание .version
    S->>N: docker exec nginx -s reload
    
    N->>N: Graceful reload
    Note over N: Новые запросы → новая версия<br/>Текущие соединения → старая версия
    
    N->>U: Обслуживание новой версии
    
    S-->>D: Telegram notification: ✓ Deployed
```

### 7.3 Откат (Rollback)

```bash
#!/bin/bash
# /opt/balancer/scripts/rollback-frontend.sh

SERVICE_NAME=$1
VERSION=$2  # Опционально: номер версии или "previous"

PROJECT_DIR="/opt/balancer"
STATIC_DIR="$PROJECT_DIR/static/$SERVICE_NAME"
DEPLOY_DIR="$PROJECT_DIR/deployments/$SERVICE_NAME"

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name> [version]"
    echo "Example: $0 myapp previous"
    echo "Example: $0 myapp 2025-11-06_10-30-15"
    exit 1
fi

# Определение версии для отката
if [ -z "$VERSION" ] || [ "$VERSION" == "previous" ]; then
    # Найти предыдущую версию
    ROLLBACK_VERSION=$(ls -t "$DEPLOY_DIR" | grep -v "current" | sed -n '2p')
else
    ROLLBACK_VERSION=$VERSION
fi

ROLLBACK_DIR="$DEPLOY_DIR/$ROLLBACK_VERSION"

if [ ! -d "$ROLLBACK_DIR" ]; then
    echo "Error: Version $ROLLBACK_VERSION not found"
    echo "Available versions:"
    ls -1 "$DEPLOY_DIR" | grep -v "current"
    exit 1
fi

echo "=== Frontend Rollback ==="
echo "Service: $SERVICE_NAME"
echo "Rolling back to: $ROLLBACK_VERSION"
read -p "Continue? (yes/no): " confirm

[ "$confirm" != "yes" ] && exit 0

# Копирование версии
rsync -av --delete "$ROLLBACK_DIR/" "$STATIC_DIR/"

# Reload Nginx
docker exec nginx-proxy nginx -s reload

echo "✓ Rollback complete"

# Уведомление
bash "$PROJECT_DIR/scripts/telegram-alert.sh" \
    "⏪ Frontend rollback\n\nService: $SERVICE_NAME\nVersion: $ROLLBACK_VERSION" \
    2>/dev/null || true
```

---

## 8. Примеры использования

### 8.1 Добавление React приложения (Static)

```bash
# На сервере
cd /opt/balancer
sudo bash scripts/add-service.sh

# Ввод:
# Имя: myapp
# Поддомен: app
# Домен: example.ru
# Категория: 2 (Frontend Static)
# 
# Результат: https://app.example.ru готов
# Директория: /opt/balancer/static/myapp/

# На локальной машине разработчика
cd my-react-app
npm run build

# Деплой
rsync -av --delete dist/ user@server:/opt/balancer/static/myapp/

# Или через скрипт на сервере
bash /opt/balancer/scripts/deploy-frontend.sh myapp ./dist
```

### 8.2 Добавление FastAPI бэкенда

```bash
sudo bash scripts/add-service.sh

# Ввод:
# Имя: api
# Поддомен: api
# Домен: example.ru
# Категория: 1 (Backend API)
# Тип: 1 (FastAPI)
# Контейнер: fastapi-app
# Порт: 8000
```

### 8.3 Добавление Next.js (SSR)

```bash
sudo bash scripts/add-service.sh

# Ввод:
# Имя: webapp
# Поддомен: www
# Домен: example.ru
# Категория: 3 (Frontend Container)
# Контейнер: nextjs-app
# Порт: 3000
```

### 8.4 Мониторинг статики

```bash
# Проверка версии
curl https://app.example.ru/.version

# Проверка cache headers
curl -I https://app.example.ru/assets/main.js

# Размер директории
du -sh /opt/balancer/static/myapp/

# Список версий
ls -lh /opt/balancer/deployments/myapp/
```

---

## 9. Сравнительная таблица подходов

| Параметр | Static Mount | Proxy Container |
|----------|-------------|-----------------|
| **RAM usage** | ~80MB (1 Nginx) | ~160MB (2 Nginx) |
| **Latency** | ~2-5ms | ~5-10ms |
| **Деплой** | Copy files + reload | Build + restart |
| **Rollback** | Instant | Requires rebuild |
| **Cache control** | Nginx config | Upstream + Nginx |
| **Hot reload** | Yes (nginx -s reload) | Container restart |
| **Isolation** | Low | High |
| **Complexity** | Low | Medium |
| **Best for** | SPA builds, static | SSR, custom logic |

---

## 10. Чек-лист миграции

Для существующих сервисов, которые нужно перевести на direct mount:

```
☐ 1. Backup текущего сервиса
   ☐ Экспорт конфигурации
   ☐ Backup контента

☐ 2. Подготовка
   ☐ Создать директорию в /static/
   ☐ Скопировать контент из контейнера
   ☐ Проверить права доступа

☐ 3. Создание новой конфигурации
   ☐ Запустить add-service.sh
   ☐ Выбрать Frontend Static
   ☐ Указать существующий домен

☐ 4. Переключение
   ☐ Удалить старую конфигурацию
   ☐ Остановить старый контейнер
   ☐ Reload Nginx

☐ 5. Проверка
   ☐ Тест доступности
   ☐ Проверка логов
   ☐ Мониторинг производительности

☐ 6. Очистка
   ☐ Удалить старый контейнер
   ☐ Удалить старые volumes
```

---

## Заключение

Добавление поддержки прямого монтирования статики обеспечивает:

✅ **Снижение потребления ресурсов на 50%**  
✅ **Упрощение деплоя фронтендов**  
✅ **Мгновенные rollback без rebuild**  
✅ **Лучшая производительность**  
✅ **Гибкость архитектуры**

Используйте **Static Mount** для:
- React, Vue, Angular builds
- Простых статических сайтов
- Landing pages
- Documentation sites

Используйте **Proxy Container** для:
- Next.js, Nuxt.js (SSR)
- Сложных Nginx конфигураций
- Когда нужна полная изоляция

---

**Конец дополнения**
