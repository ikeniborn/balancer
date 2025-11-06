---
title: "Развертывание системы"
section: "7"
version: "2.0"
category: "deployment"
updated: "2025-11-06"
tags: [deployment, installation, server-setup, docker, scripts]
related:
  - 006a_docker-compose.md
  - 007a_init-script.md
  - 007b_add-service-script.md
  - 009_operations.md
---

# 7. Развертывание

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

[◀ Назад к оглавлению](INDEX.md) | [Следующий раздел ▶](009_operations.md)

