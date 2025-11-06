# 2. Обновленная структура проекта

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

