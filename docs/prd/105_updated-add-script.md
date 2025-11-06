# 5. Обновленный скрипт добавления сервиса

## 5. Обновленный скрипт добавления

```bash
#!/bin/bash
# /opt/balancer/scripts/add-service.sh
# UPDATED VERSION 2.1 - С поддержкой разных типов подключения

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NGINX_CONF_DIR="$PROJECT_DIR/nginx/conf.d"
TEMPLATES_DIR="$PROJECT_DIR/templates"
STATIC_DIR="$PROJECT_DIR/static"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Добавление нового сервиса          ║${NC}"
echo -e "${BLUE}║     Version 2.1 - Extended             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"

# Загрузка переменных окружения
if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    echo -e "${RED}Ошибка: .env файл не найден${NC}"
    exit 1
fi

# Функции валидации (как в предыдущей версии)
validate_domain() {
    local domain=$1
    if [[ ! $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        echo -e "${RED}Ошибка: Некорректный формат домена${NC}"
        return 1
    fi
    return 0
}

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

# === НОВАЯ ФУНКЦИЯ: Выбор типа сервиса ===
select_service_category() {
    echo -e "\n${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Категория сервиса                  ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}\n"
    
    echo -e "${YELLOW}Выберите категорию сервиса:${NC}"
    echo ""
    echo "  ${GREEN}1) Backend API${NC}"
    echo "     └─ FastAPI, Django, Node.js, другие API"
    echo ""
    echo "  ${GREEN}2) Frontend (Static)${NC}"
    echo "     └─ React, Vue, Angular билды (рекомендуется)"
    echo ""
    echo "  ${GREEN}3) Frontend (Container)${NC}"
    echo "     └─ SSR приложения, кастомный Nginx"
    echo ""
    echo "  ${GREEN}4) Database (TCP Stream)${NC}"
    echo "     └─ PostgreSQL, MySQL, CouchDB"
    echo ""
    
    read -p "Ваш выбор (1-4): " CATEGORY
    
    case $CATEGORY in
        1) CATEGORY_TYPE="backend";;
        2) CATEGORY_TYPE="frontend-static";;
        3) CATEGORY_TYPE="frontend-proxy";;
        4) CATEGORY_TYPE="database";;
        *) echo -e "${RED}Некорректный выбор${NC}"; return 1;;
    esac
    
    echo -e "${GREEN}✓ Выбрана категория: $CATEGORY_TYPE${NC}"
    return 0
}

# === НОВАЯ ФУНКЦИЯ: Конфигурация Backend ===
configure_backend_service() {
    echo -e "\n${CYAN}═══ Backend API конфигурация ═══${NC}\n"
    
    echo -e "${YELLOW}Тип Backend API:${NC}"
    echo "1. FastAPI"
    echo "2. Django / Flask"
    echo "3. Node.js / Express"
    echo "4. Other HTTP API"
    read -p "Выбор (1-4): " backend_type
    
    case $backend_type in
        1) SERVICE_TEMPLATE="service-fastapi.conf.tmpl";;
        2|3|4) SERVICE_TEMPLATE="service-http.conf.tmpl";;
        *) SERVICE_TEMPLATE="service-http.conf.tmpl";;
    esac
    
    read -p "Имя Docker контейнера бэкенда: " BACKEND_HOST
    read -p "Порт бэкенда: " BACKEND_PORT
    
    read -p "Включить IP-фильтрацию? (y/n): " IP_FILTER
    if [ "$IP_FILTER" == "y" ]; then
        read -p "Разрешенная подсеть (например: 192.168.1.0/24): " ALLOWED_SUBNET
    fi
    
    CONFIG_SUBDIR="proxy"
}

# === НОВАЯ ФУНКЦИЯ: Конфигурация Frontend Static ===
configure_frontend_static() {
    echo -e "\n${CYAN}═══ Frontend Static конфигурация ═══${NC}\n"
    
    echo -e "${GREEN}Этот режим монтирует статические файлы напрямую в Nginx${NC}"
    echo -e "${GREEN}Нет дополнительного контейнера = меньше ресурсов${NC}\n"
    
    SERVICE_TEMPLATE="service-frontend-static.conf.tmpl"
    CONFIG_SUBDIR="static"
    
    # Создание директории для статики
    STATIC_SERVICE_DIR="$STATIC_DIR/$SERVICE_NAME"
    mkdir -p "$STATIC_SERVICE_DIR"
    
    echo -e "${YELLOW}Директория для статики создана:${NC} $STATIC_SERVICE_DIR"
    echo -e "${YELLOW}После настройки скопируйте ваш билд в:${NC}"
    echo -e "  ${CYAN}$STATIC_SERVICE_DIR/${NC}\n"
    
    # Создание placeholder файлов
    cat > "$STATIC_SERVICE_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Service Placeholder</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            text-align: center;
            padding: 2rem;
            background: rgba(0,0,0,0.2);
            border-radius: 10px;
        }
        h1 { margin-bottom: 1rem; }
        .status { color: #4ade80; font-size: 1.2rem; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Service Ready</h1>
        <p class="status">Placeholder page - deploy your application</p>
        <p>Service: <strong id="serviceName"></strong></p>
        <p><small>Replace this index.html with your build</small></p>
    </div>
    <script>
        document.getElementById('serviceName').textContent = window.location.hostname;
    </script>
</body>
</html>
EOF
    
    echo "1.0.0-placeholder" > "$STATIC_SERVICE_DIR/.version"
    
    echo -e "${GREEN}✓ Placeholder файлы созданы${NC}"
    
    BACKEND_HOST=""
    BACKEND_PORT=""
}

# === НОВАЯ ФУНКЦИЯ: Конфигурация Frontend Proxy ===
configure_frontend_proxy() {
    echo -e "\n${CYAN}═══ Frontend Container конфигурация ═══${NC}\n"
    
    echo -e "${YELLOW}Используйте этот режим для:${NC}"
    echo "  - SSR приложений (Next.js, Nuxt.js)"
    echo "  - Сложных конфигураций Nginx"
    echo "  - Когда нужна изоляция в контейнере"
    echo ""
    
    SERVICE_TEMPLATE="service-frontend-proxy.conf.tmpl"
    CONFIG_SUBDIR="external"
    
    read -p "Имя Docker контейнера frontend: " BACKEND_HOST
    read -p "Порт frontend контейнера: " BACKEND_PORT
}

# === НОВАЯ ФУНКЦИЯ: Конфигурация Database ===
configure_database() {
    echo -e "\n${CYAN}═══ Database TCP Stream конфигурация ═══${NC}\n"
    
    echo -e "${YELLOW}Тип базы данных:${NC}"
    echo "1. PostgreSQL (5432)"
    echo "2. MySQL/MariaDB (3306)"
    echo "3. CouchDB (5984)"
    echo "4. MongoDB (27017)"
    echo "5. Other"
    read -p "Выбор (1-5): " db_type
    
    case $db_type in
        1) DEFAULT_PORT=5432; DB_NAME="PostgreSQL";;
        2) DEFAULT_PORT=3306; DB_NAME="MySQL";;
        3) DEFAULT_PORT=5984; DB_NAME="CouchDB";;
        4) DEFAULT_PORT=27017; DB_NAME="MongoDB";;
        5) DEFAULT_PORT=""; DB_NAME="Custom";;
    esac
    
    read -p "Имя Docker контейнера БД: " BACKEND_HOST
    
    if [ -n "$DEFAULT_PORT" ]; then
        read -p "Порт БД [$DEFAULT_PORT]: " BACKEND_PORT
        BACKEND_PORT=${BACKEND_PORT:-$DEFAULT_PORT}
    else
        read -p "Порт БД: " BACKEND_PORT
    fi
    
    read -p "Внешний TCP порт [$BACKEND_PORT]: " EXTERNAL_PORT
    EXTERNAL_PORT=${EXTERNAL_PORT:-$BACKEND_PORT}
    
    echo -e "\n${YELLOW}⚠ ВАЖНО: Безопасность${NC}"
    echo "Рекомендуется ограничить доступ по IP"
    read -p "Настроить IP-фильтрацию через UFW? (y/n): " SETUP_UFW
    
    if [ "$SETUP_UFW" == "y" ]; then
        read -p "Разрешенная подсеть (например: 192.168.1.0/24): " ALLOWED_SUBNET
    fi
    
    CONFIG_SUBDIR=""
}

# === ОСНОВНОЙ ПРОЦЕСС ===

# Сбор базовой информации
echo -e "${BLUE}═══ Базовые параметры ═══${NC}\n"

read -p "Имя сервиса (латиница, без пробелов): " SERVICE_NAME
SERVICE_NAME=$(echo "$SERVICE_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_-')

read -p "Поддомен (например: api): " SUBDOMAIN
read -p "Основной домен (например: example.ru): " MAIN_DOMAIN
DOMAIN="${SUBDOMAIN}.${MAIN_DOMAIN}"

validate_domain "$DOMAIN" || exit 1

# Выбор категории
select_service_category || exit 1

# Конфигурация в зависимости от категории
case $CATEGORY_TYPE in
    "backend")
        configure_backend_service
        ;;
    "frontend-static")
        configure_frontend_static
        ;;
    "frontend-proxy")
        configure_frontend_proxy
        ;;
    "database")
        configure_database
        ;;
esac

# Проверка DNS (кроме database)
if [ "$CATEGORY_TYPE" != "database" ]; then
    check_dns "$DOMAIN" || exit 1
fi

# === ПОДТВЕРЖДЕНИЕ ===
echo -e "\n${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Подтверждение конфигурации         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"

echo "Имя сервиса: ${GREEN}$SERVICE_NAME${NC}"
echo "Категория: ${GREEN}$CATEGORY_TYPE${NC}"
echo "Домен: ${GREEN}$DOMAIN${NC}"

if [ "$CATEGORY_TYPE" != "frontend-static" ] && [ "$CATEGORY_TYPE" != "database" ]; then
    echo "Бэкенд: ${GREEN}$BACKEND_HOST:$BACKEND_PORT${NC}"
fi

if [ "$CATEGORY_TYPE" == "frontend-static" ]; then
    echo "Статика: ${GREEN}$STATIC_SERVICE_DIR${NC}"
fi

if [ "$CATEGORY_TYPE" == "database" ]; then
    echo "Бэкенд: ${GREEN}$BACKEND_HOST:$BACKEND_PORT${NC}"
    echo "Внешний порт: ${GREEN}$EXTERNAL_PORT${NC}"
fi

if [ -n "$CONFIG_SUBDIR" ]; then
    echo "Конфиг: ${GREEN}conf.d/$CONFIG_SUBDIR/$SERVICE_NAME.conf${NC}"
else
    echo "Конфиг: ${GREEN}conf.d/streams.conf${NC}"
fi

echo ""
read -p "Подтвердите создание (yes/no): " CONFIRM
[ "$CONFIRM" != "yes" ] && { echo -e "${RED}Отменено${NC}"; exit 0; }

# === СОЗДАНИЕ КОНФИГУРАЦИИ ===
echo -e "\n${YELLOW}Создание конфигурации...${NC}"

if [ "$CATEGORY_TYPE" != "database" ]; then
    # HTTP/HTTPS конфигурация
    
    # Создание поддиректории если нужно
    if [ -n "$CONFIG_SUBDIR" ]; then
        mkdir -p "$NGINX_CONF_DIR/$CONFIG_SUBDIR"
        CONFIG_FILE="$NGINX_CONF_DIR/$CONFIG_SUBDIR/${SERVICE_NAME}.conf"
        
        # Создать поддиректорию для логов
        mkdir -p "$PROJECT_DIR/logs/nginx/$CONFIG_SUBDIR"
    else
        CONFIG_FILE="$NGINX_CONF_DIR/${SERVICE_NAME}.conf"
    fi
    
    # Генерация конфига
    sed -e "s/{SERVICE_NAME}/$SERVICE_NAME/g" \
        -e "s/{DOMAIN}/$DOMAIN/g" \
        -e "s/{BACKEND_HOST}/$BACKEND_HOST/g" \
        -e "s/{BACKEND_PORT}/$BACKEND_PORT/g" \
        "$TEMPLATES_DIR/$SERVICE_TEMPLATE" > "$CONFIG_FILE"
    
    # IP-фильтрация для backend
    if [ "$IP_FILTER" == "y" ] && [ -n "$ALLOWED_SUBNET" ]; then
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

# $SERVICE_NAME - $DB_NAME
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
    if [ "$SETUP_UFW" == "y" ]; then
        echo -e "${YELLOW}Настройка UFW...${NC}"
        
        # Удалить общее правило если есть
        ufw delete allow "$EXTERNAL_PORT/tcp" 2>/dev/null || true
        
        # Добавить ограниченное правило
        ufw allow from "$ALLOWED_SUBNET" to any port "$EXTERNAL_PORT" proto tcp comment "$SERVICE_NAME"
        ufw reload
        
        echo -e "${GREEN}✓ UFW правило добавлено${NC}"
    else
        echo -e "${YELLOW}⚠ Не забудьте открыть порт $EXTERNAL_PORT в UFW и docker-compose.yml${NC}"
    fi
fi

# === ПРОВЕРКА И ПЕРЕЗАГРУЗКА ===
echo -e "\n${YELLOW}Проверка конфигурации Nginx...${NC}"
docker exec nginx-proxy nginx -t || {
    echo -e "${RED}✗ Ошибка в конфигурации${NC}"
    [ -f "$CONFIG_FILE" ] && rm "$CONFIG_FILE"
    exit 1
}
echo -e "${GREEN}✓ Конфигурация валидна${NC}"

echo -e "\n${YELLOW}Перезагрузка Nginx...${NC}"
docker exec nginx-proxy nginx -s reload || {
    echo -e "${RED}✗ Ошибка перезагрузки${NC}"
    exit 1
}
echo -e "${GREEN}✓ Nginx перезагружен${NC}"

# === УВЕДОМЛЕНИЕ ===
MESSAGE="✅ Новый сервис добавлен\n\n"
MESSAGE+="Сервис: $SERVICE_NAME\n"
MESSAGE+="Категория: $CATEGORY_TYPE\n"
MESSAGE+="Домен: $DOMAIN"

bash "$SCRIPT_DIR/telegram-alert.sh" "$MESSAGE" 2>/dev/null || true

# === ИТОГОВАЯ ИНФОРМАЦИЯ ===
echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Сервис успешно добавлен!          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"

if [ "$CATEGORY_TYPE" == "frontend-static" ]; then
    echo -e "${CYAN}Следующие шаги для деплоя статики:${NC}\n"
    echo -e "1. Скопируйте ваш билд:"
    echo -e "   ${YELLOW}rsync -av dist/ user@server:$STATIC_SERVICE_DIR/${NC}"
    echo -e ""
    echo -e "2. Или используйте скрипт деплоя:"
    echo -e "   ${YELLOW}bash scripts/deploy-frontend.sh $SERVICE_NAME${NC}"
    echo -e ""
    echo -e "3. Проверьте доступность:"
    echo -e "   ${YELLOW}curl -I https://$DOMAIN${NC}\n"
    
elif [ "$CATEGORY_TYPE" != "database" ]; then
    echo -e "Доступен по адресу: ${GREEN}https://$DOMAIN${NC}"
    echo -e "Проверка: ${YELLOW}curl -I https://$DOMAIN${NC}\n"
else
    echo -e "Доступен по порту: ${GREEN}$EXTERNAL_PORT${NC}"
    echo -e "Проверка: ${YELLOW}telnet $MAIN_DOMAIN $EXTERNAL_PORT${NC}\n"
fi

if [ -n "$CONFIG_SUBDIR" ]; then
    echo -e "Конфиг: ${YELLOW}$NGINX_CONF_DIR/$CONFIG_SUBDIR/$SERVICE_NAME.conf${NC}"
    echo -e "Логи: ${YELLOW}tail -f $PROJECT_DIR/logs/nginx/$CONFIG_SUBDIR/${SERVICE_NAME}-*.log${NC}\n"
else
    echo -e "Логи: ${YELLOW}tail -f $PROJECT_DIR/logs/nginx/stream-*.log${NC}\n"
fi

echo -e "${BLUE}═══════════════════════════════════════${NC}"
```

---

