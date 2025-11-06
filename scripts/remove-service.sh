#!/bin/bash
# /opt/balancer/scripts/remove-service.sh
# Безопасное удаление сервиса

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
