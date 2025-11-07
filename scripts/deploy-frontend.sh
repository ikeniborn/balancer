#!/bin/bash
# /opt/balancer/scripts/deploy-frontend.sh
# Скрипт для деплоя статического фронтенда

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SERVICE_NAME=$1
BUILD_PATH=$2

if [ -z "$SERVICE_NAME" ] || [ -z "$BUILD_PATH" ]; then
    echo -e "${RED}Usage: $0 <service-name> <build-path>${NC}"
    echo "Example: $0 myapp ./dist"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STATIC_DIR="$PROJECT_DIR/static/$SERVICE_NAME"
DEPLOY_DIR="$PROJECT_DIR/deployments/$SERVICE_NAME"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="$DEPLOY_DIR/$TIMESTAMP"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Frontend Deployment                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"

echo -e "${YELLOW}Service:${NC} $SERVICE_NAME"
echo -e "${YELLOW}Source:${NC} $BUILD_PATH"
echo -e "${YELLOW}Target:${NC} $STATIC_DIR"
echo ""

# Проверка существования build path
if [ ! -d "$BUILD_PATH" ]; then
    echo -e "${RED}Ошибка: Директория $BUILD_PATH не найдена${NC}"
    exit 1
fi

# Создание backup текущей версии
if [ -d "$STATIC_DIR" ] && [ "$(ls -A $STATIC_DIR)" ]; then
    echo -e "${YELLOW}Создание backup текущей версии...${NC}"
    mkdir -p "$BACKUP_DIR"
    cp -r "$STATIC_DIR"/* "$BACKUP_DIR/"
    echo -e "${GREEN}✓ Backup создан: $BACKUP_DIR${NC}"
else
    echo -e "${YELLOW}Первичный деплой - backup не требуется${NC}"
    mkdir -p "$DEPLOY_DIR"
fi

# Деплой новой версии
echo -e "\n${YELLOW}Деплой новой версии...${NC}"
mkdir -p "$STATIC_DIR"
rsync -av --delete "$BUILD_PATH/" "$STATIC_DIR/"

# Создание .version файла
VERSION=$(git describe --tags --always 2>/dev/null || echo "$TIMESTAMP")
echo "$VERSION" > "$STATIC_DIR/.version"

echo -e "${GREEN}✓ Развернута версия: $VERSION${NC}"

# Создание symlink на текущую версию
if [ -d "$BACKUP_DIR" ]; then
    ln -sfn "$BACKUP_DIR" "$DEPLOY_DIR/current"
fi

# Проверка Nginx конфигурации
echo -e "\n${YELLOW}Проверка Nginx конфигурации...${NC}"
if docker exec nginx-proxy nginx -t > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Конфигурация валидна${NC}"
else
    echo -e "${RED}✗ Ошибка конфигурации Nginx${NC}"
    echo -e "${YELLOW}Откат к предыдущей версии...${NC}"
    if [ -d "$BACKUP_DIR" ]; then
        rsync -av --delete "$BACKUP_DIR/" "$STATIC_DIR/"
        echo -e "${GREEN}✓ Откат выполнен${NC}"
    fi
    exit 1
fi

# Reload Nginx
echo -e "${YELLOW}Перезагрузка Nginx...${NC}"
if docker exec nginx-proxy nginx -s reload > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Nginx перезагружен${NC}"
else
    echo -e "${RED}✗ Ошибка перезагрузки Nginx${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Deployment Complete                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"

echo -e "${BLUE}Версия:${NC} $VERSION"
echo -e "${BLUE}Timestamp:${NC} $TIMESTAMP"
echo -e "${BLUE}Backup:${NC} $BACKUP_DIR"
echo ""

# Очистка старых бэкапов (старше 7 дней)
echo -e "${YELLOW}Очистка старых backup (>7 дней)...${NC}"
find "$DEPLOY_DIR" -maxdepth 1 -type d -mtime +7 ! -name "current" -exec rm -rf {} \; 2>/dev/null || true
echo -e "${GREEN}✓ Очистка завершена${NC}\n"

# Отправка уведомления
bash "$SCRIPT_DIR/telegram-alert.sh" \
    "🚀 Frontend deployed\n\nService: $SERVICE_NAME\nVersion: $VERSION\nTime: $TIMESTAMP" \
    2>/dev/null || true

echo -e "${BLUE}Проверка:${NC} curl -I https://<your-domain>"
echo ""
