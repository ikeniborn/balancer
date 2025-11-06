# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Язык документации

Используем русский язык (ru) для всей документации и взаимодействия с пользователем.

## Обзор проекта

**Balancer** - централизованная система reverse proxy на базе Nginx для управления доступом к Docker-контейнерам через HTTPS с автоматическим управлением SSL-сертификатами Let's Encrypt.

### Целевая структура развертывания

Система будет установлена в `/opt/balancer/` со следующей архитектурой:

```
/opt/balancer/
├── nginx/                     # Конфигурации Nginx
│   ├── conf.d/
│   │   ├── proxy/            # Backend API конфиги
│   │   ├── static/           # Static Frontend конфиги (Direct Mount)
│   │   ├── external/         # Proxy Frontend конфиги (SSR)
│   │   └── streams.conf      # TCP Database конфиги
│   └── snippets/             # Переиспользуемые блоки
├── static/                   # Статический контент для direct mount
├── scripts/                  # Bash-скрипты управления
├── templates/                # Шаблоны конфигураций
└── deployments/              # История деплоев
```

## Ключевая архитектура

### 4 типа подключения сервисов

Проект поддерживает 4 различных типа подключения сервисов, каждый с уникальной архитектурой:

1. **Backend API (Proxy)**
   - Для: FastAPI, Django, Node.js, другие API сервисы
   - Путь: Client → Nginx-Proxy → Backend Container → Response
   - Конфиги: `conf.d/proxy/`

2. **Frontend Static (Direct Mount)** ⭐ Оптимизированный подход
   - Для: React, Vue, Angular (после npm run build), статические сайты
   - Путь: Client → Nginx-Proxy → Static Files (Volume) → Response
   - Конфиги: `conf.d/static/`
   - Файлы: `/opt/balancer/static/{app-name}/`
   - Преимущества: -50% RAM, -60% latency, мгновенный rollback
   - Ключевое отличие: файлы монтируются напрямую в Nginx через volume, без дополнительного контейнера

3. **Frontend Container (Proxy)**
   - Для: Next.js/Nuxt.js с SSR, приложения требующие отдельный Nginx
   - Путь: Client → Nginx-Proxy → Frontend-Nginx Container → Response
   - Конфиги: `conf.d/external/`

4. **Database (TCP Stream)**
   - Для: PostgreSQL, MySQL, CouchDB
   - Путь: Client → Nginx TCP Stream → Database Container
   - Конфиги: `conf.d/streams.conf`

### Docker сети

- **proxy_network** (172.20.0.0/16) - для nginx-proxy, certbot, healthcheck
- **internal_network** (172.22.0.0/16) - internal only, для изоляции БД
- Сервисы подключаются к обеим сетям по необходимости

## Скрипты управления

Основные bash-скрипты в `scripts/`:

- `init-balancer.sh` - первоначальная инициализация системы
- `add-service.sh` - добавление нового сервиса (интерактивный выбор типа)
- `remove-service.sh` - удаление сервиса
- `deploy-frontend.sh` - деплой статического фронтенда с версионированием
- `rollback-frontend.sh` - откат фронтенда на предыдущую версию
- `health-check.sh` - мониторинг здоровья сервисов
- `telegram-alert.sh` - отправка Telegram уведомлений

## Критичные концепции

### Direct Mount vs Proxy Container для фронтендов

**Используйте Direct Mount** (Frontend Static) когда:
- Приложение генерирует статический билд (React, Vue, Angular)
- Не требуется SSR
- Нужна максимальная производительность

**Используйте Proxy Container** когда:
- Приложение использует SSR (Next.js, Nuxt.js)
- Требуется кастомная Nginx конфигурация в отдельном контейнере
- Нужна полная изоляция

### Workflow деплоя Static Frontend

```bash
# 1. Локально
npm run build

# 2. Деплой на сервер
bash /opt/balancer/scripts/deploy-frontend.sh myapp ./dist

# 3. Откат при необходимости
bash /opt/balancer/scripts/rollback-frontend.sh myapp previous
```

История версий сохраняется в `/opt/balancer/deployments/{app-name}/`.

## Документация проекта

Полная документация находится в `docs/prd/` и структурирована на 31 модульный файл:

### Навигация по документации
- **[INDEX.md](docs/prd/INDEX.md)** - главный навигационный индекс со ссылками на все разделы
- **[README.md](docs/prd/README.md)** - руководство по документам
- **[CHEATSHEET.md](docs/prd/CHEATSHEET.md)** - шпаргалка по типам подключения

### Структура ПРД
Документация разбита на логические модули с маской `NNN_name.md`:

**Основной ПРД v2.0 (файлы 001-012):**
- 001-005: Обзор, архитектура, требования, структура проекта
- 006a-006e: Конфигурации (Docker Compose, Nginx, snippets, шаблоны)
- 007a-007f: Скрипты автоматизации (init, add-service, health-check и др.)
- 008-012: Развертывание, эксплуатация, troubleshooting, приложения, глоссарий

**Расширение Direct Mount v2.1 (файлы 100-109):**
- Оптимизация подключения фронтендов через прямое монтирование статических файлов
- Обновленные конфигурации, скрипты и workflow для Direct Mount

**Архив:**
- Оригинальные монолитные документы сохранены в `docs/prd/archive/`

## Важные технические детали

- **Целевые метрики**: Uptime > 99.5%, время добавления сервиса < 5 минут
- **SSL**: Автоматическое обновление Let's Encrypt сертификатов каждые 12 часов
- **Мониторинг**: Health checks каждые 5 минут с Telegram алертами
- **Безопасность**: UFW firewall, IP-фильтрация для БД, Fail2Ban
- **Graceful reload**: Nginx reload без downtime при изменении конфигураций
