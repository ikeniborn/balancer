#!/bin/bash
# /opt/balancer/scripts/rollback-frontend.sh
# Откат фронтенда на предыдущую версию

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SERVICE_NAME=$1
VERSION=$2  # Опционально: номер версии или "previous"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STATIC_DIR="$PROJECT_DIR/static/$SERVICE_NAME"
DEPLOY_DIR="$PROJECT_DIR/deployments/$SERVICE_NAME"

echo -e "${YELLOW}╔════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║     Frontend Rollback                  ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════╝${NC}\n"

if [ -z "$SERVICE_NAME" ]; then
    echo -e "${RED}Usage: $0 <service-name> [version]${NC}"
    echo "Example: $0 myapp previous"
    echo "Example: $0 myapp 2025-11-06_10-30-15"
    exit 1
fi

# Проверка существования директории деплоев
if [ ! -d "$DEPLOY_DIR" ]; then
    echo -e "${RED}Ошибка: Директория деплоев не найдена${NC}"
    echo "Сервис: $SERVICE_NAME"
    exit 1
fi

# Определение версии для отката
if [ -z "$VERSION" ] || [ "$VERSION" == "previous" ]; then
    # Найти предыдущую версию
    ROLLBACK_VERSION=$(ls -t "$DEPLOY_DIR" | grep -v "current" | sed -n '2p')
    if [ -z "$ROLLBACK_VERSION" ]; then
        echo -e "${RED}Ошибка: Предыдущая версия не найдена${NC}"
        echo -e "${YELLOW}Доступные версии:${NC}"
        ls -1 "$DEPLOY_DIR" | grep -v "current"
        exit 1
    fi
else
    ROLLBACK_VERSION=$VERSION
fi

ROLLBACK_DIR="$DEPLOY_DIR/$ROLLBACK_VERSION"

if [ ! -d "$ROLLBACK_DIR" ]; then
    echo -e "${RED}Ошибка: Версия $ROLLBACK_VERSION не найдена${NC}"
    echo -e "\n${YELLOW}Доступные версии:${NC}"
    ls -1 "$DEPLOY_DIR" | grep -v "current"
    exit 1
fi

echo -e "${YELLOW}Сервис:${NC} $SERVICE_NAME"
echo -e "${YELLOW}Откат к версии:${NC} $ROLLBACK_VERSION"
echo ""

read -p "Продолжить? (yes/no): " confirm
[ "$confirm" != "yes" ] && { echo -e "${YELLOW}Отменено${NC}"; exit 0; }

# Копирование версии
echo -e "\n${YELLOW}Выполнение отката...${NC}"
rsync -av --delete "$ROLLBACK_DIR/" "$STATIC_DIR/"
echo -e "${GREEN}✓ Файлы скопированы${NC}"

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
echo -e "${GREEN}║     Rollback Complete                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"

echo -e "${BLUE}Сервис:${NC} $SERVICE_NAME"
echo -e "${BLUE}Версия:${NC} $ROLLBACK_VERSION"
echo ""

# Уведомление
bash "$SCRIPT_DIR/telegram-alert.sh" \
    "⏪ Frontend rollback\n\nService: $SERVICE_NAME\nVersion: $ROLLBACK_VERSION" \
    2>/dev/null || true

echo -e "${BLUE}Проверка:${NC} curl -I https://<your-domain>"
echo ""
