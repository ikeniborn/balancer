# 6.2 Скрипт добавления сервиса

# /opt/balancer/scripts/add-service.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NGINX_CONF_DIR="$PROJECT_DIR/nginx/conf.d"
TEMPLATES_DIR="$PROJECT_DIR/templates"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Добавление нового сервиса          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"

# Загрузка переменных окружения
if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    echo -e "${RED}Ошибка: .env файл не найден${NC}"
    exit 1
fi

# Функция валидации домена
validate_domain() {
    local domain=$1
    if [[ ! $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        echo -e "${RED}Ошибка: Некорректный формат домена${NC}"
        return 1
    fi
    return 0
}

# Функция проверки DNS
check_dns() {
    local domain=$1
    echo -e "${YELLOW}Проверка DNS записи для $domain...${NC}"
    
    if host $domain > /dev/null 2>&1; then
        local ip=$(host $domain | awk '/has address/ { print $4 }' | head -1)
        local server_ip=$(curl -s ifconfig.me || curl -s icanhazip.com)
        
        echo "DNS указывает на: $ip"
        echo "IP сервера: $server_ip"
        
        if [ "$ip" == "$server_ip" ]; then
            echo -e "${GREEN}✓ DNS запись корректна${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ DNS и IP сервера не совпадают${NC}"
            read -p "Продолжить? (y/n): " confirm
            [ "$confirm" != "y" ] && return 1
        fi
    else
        echo -e "${YELLOW}⚠ DNS запись не найдена${NC}"
        read -p "Продолжить без DNS? (y/n): " confirm
        [ "$confirm" != "y" ] && return 1
    fi
    return 0
}

# Сбор информации
echo -e "${BLUE}═══ Параметры сервиса ═══${NC}\n"

read -p "Имя сервиса (латиница, без пробелов): " SERVICE_NAME
SERVICE_NAME=$(echo "$SERVICE_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_-')

read -p "Поддомен (например: api): " SUBDOMAIN
read -p "Основной домен (например: example.ru): " MAIN_DOMAIN
DOMAIN="${SUBDOMAIN}.${MAIN_DOMAIN}"

validate_domain "$DOMAIN" || exit 1

echo -e "\n${YELLOW}Типы сервисов:${NC}"
echo "1. FastAPI Backend"
echo "2. Frontend (Static/Nginx)"
echo "3. Custom HTTP"
echo "4. TCP (Database)"
read -p "Выберите тип (1-4): " SERVICE_TYPE_CHOICE

case $SERVICE_TYPE_CHOICE in
    1) SERVICE_TYPE="fastapi";;
    2) SERVICE_TYPE="frontend";;
    3) SERVICE_TYPE="http";;
    4) SERVICE_TYPE="tcp";;
    *) echo -e "${RED}Некорректный выбор${NC}"; exit 1;;
esac

read -p "Хост бэкенда (имя Docker контейнера): " BACKEND_HOST
read -p "Порт бэкенда: " BACKEND_PORT

if [ "$SERVICE_TYPE" == "tcp" ]; then
    read -p "Внешний TCP порт: " EXTERNAL_PORT
    read -p "Разрешить доступ только с определенных IP? (y/n): " RESTRICT_IP
    if [ "$RESTRICT_IP" == "y" ]; then
        read -p "Разрешенная подсеть (например: 192.168.1.0/24): " ALLOWED_SUBNET
    fi
else
    read -p "Включить IP-фильтрацию? (y/n): " IP_FILTER
    if [ "$IP_FILTER" == "y" ]; then
        read -p "Разрешенная подсеть: " ALLOWED_SUBNET
    fi
fi

# Проверка DNS
check_dns "$DOMAIN" || exit 1

# Подтверждение
echo -e "\n${BLUE}═══ Подтверждение ═══${NC}"
echo "Имя сервиса: $SERVICE_NAME"
echo "Домен: $DOMAIN"
echo "Тип: $SERVICE_TYPE"
echo "Бэкенд: $BACKEND_HOST:$BACKEND_PORT"
[ "$SERVICE_TYPE" == "tcp" ] && echo "Внешний порт: $EXTERNAL_PORT"
echo ""
read -p "Подтвердите создание (yes/no): " CONFIRM
[ "$CONFIRM" != "yes" ] && { echo -e "${RED}Отменено${NC}"; exit 0; }

# Создание конфигурации
echo -e "\n${YELLOW}Создание конфигурации...${NC}"

if [ "$SERVICE_TYPE" != "tcp" ]; then
    # HTTP/HTTPS конфигурация
    CONFIG_FILE="$NGINX_CONF_DIR/${SERVICE_NAME}.conf"
    
    # Выбор шаблона
    if [ "$SERVICE_TYPE" == "fastapi" ]; then
        TEMPLATE="$TEMPLATES_DIR/service-fastapi.conf.tmpl"
    elif [ "$SERVICE_TYPE" == "frontend" ]; then
        TEMPLATE="$TEMPLATES_DIR/service-frontend.conf.tmpl"
    else
        TEMPLATE="$TEMPLATES_DIR/service-http.conf.tmpl"
    fi
    
    # Генерация конфига
    sed -e "s/{SERVICE_NAME}/$SERVICE_NAME/g" \
        -e "s/{DOMAIN}/$DOMAIN/g" \
        -e "s/{BACKEND_HOST}/$BACKEND_HOST/g" \
        -e "s/{BACKEND_PORT}/$BACKEND_PORT/g" \
        "$TEMPLATE" > "$CONFIG_FILE"
    
    # IP-фильтрация
    if [ "$IP_FILTER" == "y" ]; then
        sed -i "/# IP фильтрация/a\    allow $ALLOWED_SUBNET;\n    deny all;" "$CONFIG_FILE"
    fi
    
    echo -e "${GREEN}✓ Конфиг создан: $CONFIG_FILE${NC}"
    
    # Получение SSL сертификата
    echo -e "\n${YELLOW}Получение SSL сертификата...${NC}"
    
    docker compose -f "$PROJECT_DIR/docker-compose.yml" run --rm certbot \
        certonly --webroot -w /var/www/certbot \
        --email "$LETSENCRYPT_EMAIL" \
        --agree-tos \
        --no-eff-email \
        -d "$DOMAIN" \
        --non-interactive || {
            echo -e "${RED}✗ Ошибка получения SSL${NC}"
            rm "$CONFIG_FILE"
            exit 1
        }
    
    echo -e "${GREEN}✓ SSL сертификат получен${NC}"
    
else
    # TCP Stream конфигурация
    STREAM_CONF="$NGINX_CONF_DIR/streams.conf"
    
    cat >> "$STREAM_CONF" << EOF

# $SERVICE_NAME - $DOMAIN
upstream ${SERVICE_NAME}_backend {
    server ${BACKEND_HOST}:${BACKEND_PORT} max_fails=3 fail_timeout=30s;
}

server {
    listen ${EXTERNAL_PORT};
    listen [::]:${EXTERNAL_PORT};
    proxy_pass ${SERVICE_NAME}_backend;
    proxy_connect_timeout 10s;
    proxy_timeout 30m;
}
EOF
    
    echo -e "${GREEN}✓ TCP stream добавлен${NC}"
    
    # Настройка UFW для TCP
    if [ "$RESTRICT_IP" == "y" ]; then
        echo -e "${YELLOW}Настройка UFW...${NC}"
        ufw allow from "$ALLOWED_SUBNET" to any port "$EXTERNAL_PORT" proto tcp comment "$SERVICE_NAME"
        echo -e "${GREEN}✓ UFW правило добавлено${NC}"
    else
        echo -e "${YELLOW}⚠ Не забудьте открыть порт $EXTERNAL_PORT в docker-compose.yml${NC}"
    fi
fi

# Проверка конфигурации
echo -e "\n${YELLOW}Проверка конфигурации Nginx...${NC}"
docker exec nginx-proxy nginx -t || {
    echo -e "${RED}✗ Ошибка в конфигурации${NC}"
    [ -f "$CONFIG_FILE" ] && rm "$CONFIG_FILE"
    exit 1
}
echo -e "${GREEN}✓ Конфигурация валидна${NC}"

# Перезагрузка Nginx
echo -e "\n${YELLOW}Перезагрузка Nginx...${NC}"
docker exec nginx-proxy nginx -s reload || {
    echo -e "${RED}✗ Ошибка перезагрузки${NC}"
    exit 1
}
echo -e "${GREEN}✓ Nginx перезагружен${NC}"

# Отправка уведомления
bash "$SCRIPT_DIR/telegram-alert.sh" "✅ Новый сервис добавлен\n\nСервис: $SERVICE_NAME\nДомен: $DOMAIN\nТип: $SERVICE_TYPE" 2>/dev/null || true

# Итоговая информация
echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Сервис успешно добавлен!          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"

if [ "$SERVICE_TYPE" != "tcp" ]; then
    echo -e "Доступен по адресу: ${GREEN}https://$DOMAIN${NC}"
    echo -e "Проверка: ${YELLOW}curl -I https://$DOMAIN${NC}"
else
    echo -e "Доступен по порту: ${GREEN}$EXTERNAL_PORT${NC}"
    echo -e "Проверка: ${YELLOW}telnet $MAIN_DOMAIN $EXTERNAL_PORT${NC}"
fi

echo -e "\nЛоги: ${YELLOW}tail -f $PROJECT_DIR/logs/nginx/${SERVICE_NAME}-*.log${NC}"
```

### 6.3 Скрипт удаления сервиса

```bash
#!/bin/bash
