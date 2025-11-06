---
title: "Архитектура системы"
section: "2"
version: "2.0"
category: "architecture"
updated: "2025-11-06"
tags: [architecture, mermaid, diagrams, docker, nginx, ssl, networks, monitoring]
related:
  - 001_index.md
  - 002_executive-summary.md
  - 004_technical-requirements.md
  - 006a_docker-compose.md
  - 008_deployment.md
---

# 2. Архитектура системы

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

[◀ Назад к оглавлению](INDEX.md) | [Следующий раздел ▶](004_technical-requirements.md)
