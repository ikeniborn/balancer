# 4. Структура проекта

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

