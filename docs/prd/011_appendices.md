# 10. Приложения

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

