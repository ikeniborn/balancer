# Balancer

> Централизованная система reverse proxy на базе Nginx для управления доступом к Docker-контейнерам через HTTPS с автоматическим управлением SSL-сертификатами Let's Encrypt

![Version](https://img.shields.io/badge/version-2.1-blue.svg)
![Docker](https://img.shields.io/badge/docker-20.10%2B-blue.svg)
![Nginx](https://img.shields.io/badge/nginx-1.24%2B-green.svg)
![License](https://img.shields.io/badge/license-Apache%202.0-orange.svg)

## О проекте

**Balancer** упрощает подключение любых сервисов (API, фронтенды, базы данных) к интернету через единую точку входа с автоматическим SSL. Система разработана для максимальной автоматизации операций и минимального времени развертывания новых сервисов.

### Ключевые возможности

- **Автоматическое управление SSL** - Let's Encrypt сертификаты с автообновлением каждые 12 часов
- **4 типа подключения** - Backend API, Static Frontend, SSR Frontend, Database TCP
- **Direct Mount оптимизация** - прямое монтирование статики: -50% RAM, -60% latency
- **Bash-автоматизация** - добавление сервиса за < 5 минут через интерактивные скрипты
- **Версионирование деплоев** - история версий с мгновенным откатом
- **Health monitoring** - проверка каждые 5 минут с Telegram алертами
- **IP-фильтрация** - защита внутренних сервисов (базы данных)
- **Graceful reload** - изменение конфигураций без downtime
- **Целевой uptime > 99.5%**

## Типы подключения сервисов

| Тип | Использование | Путь данных | Примеры |
|-----|--------------|-------------|---------|
| **Backend API** | REST API сервисы | Client → Nginx → Backend Container | FastAPI, Django, Node.js |
| **Frontend Static** | Статические сборки | Client → Nginx → Static Files (Volume) | React, Vue, Angular |
| **Frontend Container** | SSR приложения | Client → Nginx → Frontend Container | Next.js, Nuxt.js |
| **Database TCP** | Базы данных | Client → Nginx TCP → Database Container | PostgreSQL, MySQL |

### Когда использовать каждый тип?

**Frontend Static (рекомендуется для SPA)**
- ✅ Приложение генерирует статический билд (`npm run build`)
- ✅ Не требуется Server-Side Rendering
- ✅ Нужна максимальная производительность

**Frontend Container (для SSR)**
- ✅ Приложение использует SSR (Next.js, Nuxt.js)
- ✅ Требуется кастомная конфигурация Nginx

## Быстрый старт

```bash
# 1. Клонировать репозиторий
git clone <repository-url>
cd balancer

# 2. Инициализировать систему
sudo bash scripts/init-balancer.sh

# 3. Добавить первый сервис (интерактивно)
sudo bash scripts/add-service.sh

# 4. Проверить статус
docker compose ps
```

## Структура проекта

```
/opt/balancer/
├── docker-compose.yml         # Основной compose файл
├── nginx/                     # Конфигурации Nginx
│   ├── conf.d/
│   │   ├── proxy/            # Backend API конфиги
│   │   ├── static/           # Static Frontend конфиги (Direct Mount)
│   │   ├── external/         # Proxy Frontend конфиги (SSR)
│   │   └── streams.conf      # TCP Database конфиги
│   └── snippets/             # Переиспользуемые блоки (ssl, security, proxy)
├── static/                   # Статический контент для direct mount
├── scripts/                  # Bash-скрипты управления
│   ├── init-balancer.sh      # Инициализация системы
│   ├── add-service.sh        # Добавление сервиса
│   ├── remove-service.sh     # Удаление сервиса
│   ├── deploy-frontend.sh    # Деплой статического фронтенда
│   ├── rollback-frontend.sh  # Откат версии фронтенда
│   ├── health-check.sh       # Мониторинг здоровья
│   └── telegram-alert.sh     # Telegram уведомления
├── templates/                # Шаблоны конфигураций
├── deployments/              # История деплоев (версионирование)
├── logs/                     # Логи Nginx
└── docs/                     # Документация проекта
```

## Примеры использования

### React приложение (Static Frontend)

```bash
# На сервере: добавить сервис
sudo bash scripts/add-service.sh
# Выбрать: 2 (Frontend Static)
# Имя: myapp, Поддомен: app, Домен: example.ru

# Локально: собрать приложение
cd my-react-app
npm run build

# Деплой на сервер
rsync -av --delete dist/ user@server:/opt/balancer/static/myapp/

# Откат при необходимости
bash /opt/balancer/scripts/rollback-frontend.sh myapp previous
```

### FastAPI Backend

```bash
# Запустить FastAPI контейнер в сети proxy_network
docker network connect proxy_network fastapi-app

# Добавить сервис
sudo bash scripts/add-service.sh
# Выбрать: 1 (Backend API) → 1 (FastAPI)
# Контейнер: fastapi-app, Порт: 8000
```

### PostgreSQL Database

```bash
# Добавить TCP Stream
sudo bash scripts/add-service.sh
# Выбрать: 4 (Database TCP) → 1 (PostgreSQL)

# Настроить IP-фильтрацию
sudo ufw allow from 192.168.1.0/24 to any port 5432 proto tcp
```

## Управление системой

```bash
# Статус сервисов
docker compose ps

# Просмотр логов
docker compose logs -f nginx

# Graceful reload Nginx
docker exec nginx-proxy nginx -t && docker exec nginx-proxy nginx -s reload

# Health check
bash scripts/health-check.sh

# Проверка SSL сертификатов
docker compose run --rm certbot certificates
```

## Документация

Полная документация проекта находится в директории `docs/prd/`:

- **[INDEX.md](docs/prd/INDEX.md)** - главный навигационный индекс со ссылками на все разделы
- **[README.md](docs/prd/README.md)** - руководство по работе с документацией
- **[CHEATSHEET.md](docs/prd/CHEATSHEET.md)** - шпаргалка по типам подключения

### Основные разделы ПРД

- [001_index.md](docs/prd/001_index.md) - титульная страница и содержание
- [002_executive-summary.md](docs/prd/002_executive-summary.md) - обзор проекта и цели
- [003_architecture.md](docs/prd/003_architecture.md) - архитектура системы
- [004_technical-requirements.md](docs/prd/004_technical-requirements.md) - технические требования
- [005_project-structure.md](docs/prd/005_project-structure.md) - структура проекта
- [008_deployment.md](docs/prd/008_deployment.md) - инструкции по развертыванию
- [009_operations.md](docs/prd/009_operations.md) - руководство по эксплуатации

## FAQ

### Как добавить новый сервис?

```bash
sudo bash scripts/add-service.sh
```

Скрипт интерактивно проведет через процесс добавления. Весь процесс занимает < 5 минут.

### Как обновить SSL сертификат вручную?

```bash
docker compose run --rm certbot renew
docker exec nginx-proxy nginx -s reload
```

Автоматическое обновление происходит каждые 12 часов.

### Как откатить деплой фронтенда?

```bash
bash /opt/balancer/scripts/rollback-frontend.sh myapp previous
```

Доступны откаты на любую сохраненную версию из `/opt/balancer/deployments/{app-name}/`.

### Как настроить Telegram алерты?

Отредактируйте переменные в `scripts/telegram-alert.sh`:
```bash
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"
```

### Что делать при 502 Bad Gateway?

```bash
# Проверить, запущен ли контейнер бэкенда
docker ps | grep backend-name

# Проверить, в правильной ли сети
docker network inspect proxy_network

# Проверить конфигурацию Nginx
docker exec nginx-proxy nginx -t
```

### Как удалить сервис?

```bash
sudo bash scripts/remove-service.sh
```

Скрипт удалит конфигурацию Nginx и SSL сертификаты.

### Какие порты должны быть открыты?

- **80** (HTTP) - для редиректа на HTTPS
- **443** (HTTPS) - основной трафик
- **5432, 5984** (опционально) - для баз данных с IP-фильтрацией

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

## Технические требования

### Минимальные
- Ubuntu 22.04+ / Debian 10+
- 2 CPU cores
- 2 GB RAM
- 20 GB disk
- Docker 20.10+
- Docker Compose 2.0+

### Рекомендуемые
- Ubuntu 24.04 LTS
- 4 CPU cores
- 4 GB RAM
- 50 GB SSD
- Docker 24.0+
- Docker Compose 2.20+

## Архитектура Docker сетей

Система использует две изолированные сети:

- **proxy_network** (172.20.0.0/16) - для nginx-proxy, certbot, healthcheck и публичных сервисов
- **internal_network** (172.22.0.0/16) - для изоляции баз данных (internal only)

## Лицензия

Данный проект лицензирован под [Apache License 2.0](LICENSE).

```
Copyright 2025

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

---

**Версия:** 2.1
**Последнее обновление:** 2025-11-06
