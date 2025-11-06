# 6.1 Скрипт инициализации

## 6. Скрипты автоматизации

### 6.1 Скрипт инициализации

```bash
#!/bin/bash
# /opt/balancer/scripts/init-balancer.sh
# Первоначальная инициализация системы Balancer

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Balancer Initialization Script      ║${NC}"
echo -e "${BLUE}║   Nginx Reverse Proxy Setup           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Ошибка: Требуются права root${NC}"
    echo "Запустите: sudo bash $0"
    exit 1
fi

# Функция для проверки зависимостей
check_dependencies() {
    echo -e "${YELLOW}Проверка зависимостей...${NC}"
    
    local deps=("docker" "docker-compose" "curl" "openssl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            missing+=($dep)
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}Отсутствуют зависимости: ${missing[*]}${NC}"
        echo -e "${YELLOW}Установить автоматически? (y/n)${NC}"
        read -r confirm
        if [ "$confirm" == "y" ]; then
            install_dependencies
        else
            exit 1
        fi
    else
        echo -e "${GREEN}✓ Все зависимости установлены${NC}"
    fi
}

# Функция установки зависимостей
install_dependencies() {
    echo -e "${YELLOW}Установка зависимостей...${NC}"
    
    # Обновление пакетов
    apt-get update
    
    # Установка базовых утилит
    apt-get install -y curl openssl ca-certificates gnupg lsb-release
    
    # Установка Docker если отсутствует
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Установка Docker...${NC}"
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh
        rm /tmp/get-docker.sh
        systemctl enable docker
        systemctl start docker
    fi
    
    # Установка Docker Compose Plugin
    if ! docker compose version &> /dev/null; then
        echo -e "${YELLOW}Установка Docker Compose Plugin...${NC}"
        apt-get install -y docker-compose-plugin
    fi
    
    echo -e "${GREEN}✓ Зависимости установлены${NC}"
}

# Функция для сбора конфигурации
collect_configuration() {
    echo -e "\n${BLUE}═══ Конфигурация параметров ═══${NC}\n"
    
    # Email для Let's Encrypt
    while true; do
        read -p "Email для Let's Encrypt уведомлений: " LETSENCRYPT_EMAIL
        if [[ "$LETSENCRYPT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo -e "${RED}Некорректный email формат${NC}"
        fi
    done
    
    # Telegram Bot Token
    echo -e "\n${YELLOW}Для получения Telegram Bot Token:${NC}"
    echo "1. Откройте @BotFather в Telegram"
    echo "2. Отправьте команду /newbot"
    echo "3. Следуйте инструкциям"
    echo "4. Скопируйте полученный token"
    read -p "Telegram Bot Token: " TELEGRAM_BOT_TOKEN
    
    # Telegram Chat ID
    echo -e "\n${YELLOW}Для получения Chat ID:${NC}"
    echo "1. Откройте @userinfobot в Telegram"
    echo "2. Отправьте любое сообщение"
    echo "3. Скопируйте ваш ID"
    read -p "Telegram Chat ID: " TELEGRAM_CHAT_ID
    
    # Timezone
    echo -e "\n${YELLOW}Доступные временные зоны:${NC}"
    echo "1. Europe/Moscow"
    echo "2. Europe/London"
    echo "3. America/New_York"
    echo "4. Asia/Tokyo"
    echo "5. Другая (ввести вручную)"
    read -p "Выбор (1-5): " tz_choice
    
    case $tz_choice in
        1) TZ="Europe/Moscow";;
        2) TZ="Europe/London";;
        3) TZ="America/New_York";;
        4) TZ="Asia/Tokyo";;
        5) read -p "Введите timezone: " TZ;;
        *) TZ="Europe/Moscow";;
    esac
    
    echo -e "\n${GREEN}═══ Конфигурация собрана ═══${NC}"
}

# Функция создания .env файла
create_env_file() {
    echo -e "\n${YELLOW}Создание .env файла...${NC}"
    
    cat > "$PROJECT_DIR/.env" << EOF
# Balancer Configuration
# Generated: $(date)

# Let's Encrypt
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL

# Telegram Alerts
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID

# System
TZ=$TZ

# Docker Compose Project
COMPOSE_PROJECT_NAME=balancer
EOF
    
    chmod 600 "$PROJECT_DIR/.env"
    echo -e "${GREEN}✓ .env файл создан${NC}"
}

# Функция создания самоподписанного сертификата
create_self_signed_cert() {
    echo -e "\n${YELLOW}Создание самоподписанного сертификата для default сервера...${NC}"
    
    mkdir -p "$PROJECT_DIR/nginx/snippets"
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$PROJECT_DIR/nginx/snippets/self-signed.key" \
        -out "$PROJECT_DIR/nginx/snippets/self-signed.crt" \
        -subj "/C=RU/ST=Moscow/L=Moscow/O=Balancer/CN=default" \
        2>/dev/null
    
    echo -e "${GREEN}✓ Самоподписанный сертификат создан${NC}"
}

# Функция настройки UFW
setup_firewall() {
    echo -e "\n${YELLOW}Настройка UFW Firewall...${NC}"
    
    if ! command -v ufw &> /dev/null; then
        echo -e "${YELLOW}Установка UFW...${NC}"
        apt-get install -y ufw
    fi
    
    # Сброс правил
    ufw --force reset
    
    # Базовые политики
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH (текущий порт)
    SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | cut -d':' -f2 | head -1)
    [ -z "$SSH_PORT" ] && SSH_PORT=22
    ufw allow $SSH_PORT/tcp comment 'SSH'
    
    # HTTP/HTTPS
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    
    echo -e "${YELLOW}Открыть порты для баз данных? (5432, 5984)${NC}"
    echo "Рекомендуется ограничить доступ по IP позже"
    read -p "Открыть? (y/n): " open_db_ports
    
    if [ "$open_db_ports" == "y" ]; then
        ufw allow 5432/tcp comment 'PostgreSQL'
        ufw allow 5984/tcp comment 'CouchDB'
        echo -e "${YELLOW}⚠ Не забудьте настроить IP-фильтрацию позже!${NC}"
    fi
    
    # Включение UFW
    ufw --force enable
    
    echo -e "${GREEN}✓ UFW настроен${NC}"
    ufw status verbose
}

# Функция настройки Fail2Ban
setup_fail2ban() {
    echo -e "\n${YELLOW}Настроить Fail2Ban для дополнительной защиты? (y/n)${NC}"
    read -p "> " setup_f2b
    
    if [ "$setup_f2b" != "y" ]; then
        echo "Пропуск Fail2Ban"
        return
    fi
    
    if ! command -v fail2ban-server &> /dev/null; then
        echo -e "${YELLOW}Установка Fail2Ban...${NC}"
        apt-get install -y fail2ban
    fi
    
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
port = http,https
logpath = /opt/balancer/logs/nginx/*error.log

[nginx-limit-req]
enabled = true
port = http,https
logpath = /opt/balancer/logs/nginx/*error.log
maxretry = 10
EOF
    
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    echo -e "${GREEN}✓ Fail2Ban настроен${NC}"
}

# Функция создания структуры каталогов
create_directory_structure() {
    echo -e "\n${YELLOW}Создание структуры каталогов...${NC}"
    
    mkdir -p "$PROJECT_DIR"/{nginx/{conf.d,snippets,html},certbot/conf,logs/{nginx,certbot},scripts,templates,healthcheck}
    
    # Установка прав
    chown -R root:root "$PROJECT_DIR"
    chmod -R 755 "$PROJECT_DIR"
    chmod -R 755 "$PROJECT_DIR/scripts"
    
    echo -e "${GREEN}✓ Структура каталогов создана${NC}"
}

# Функция создания systemd сервиса
create_systemd_service() {
    echo -e "\n${YELLOW}Создание systemd сервиса...${NC}"
    
    cat > /etc/systemd/system/balancer.service << EOF
[Unit]
Description=Balancer - Nginx Reverse Proxy System
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart
TimeoutStartSec=0
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable balancer.service
    
    echo -e "${GREEN}✓ Systemd сервис создан и включен${NC}"
}

# Функция тестирования Telegram
test_telegram() {
    echo -e "\n${YELLOW}Тестирование Telegram уведомлений...${NC}"
    
    MESSAGE="🚀 Balancer инициализирован!%0A%0AHost: $(hostname)%0ATime: $(date '+%Y-%m-%d %H:%M:%S')"
    
    RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${MESSAGE}" \
        -d "parse_mode=HTML")
    
    if echo "$RESPONSE" | grep -q '"ok":true'; then
        echo -e "${GREEN}✓ Telegram уведомления работают${NC}"
    else
        echo -e "${RED}✗ Ошибка отправки в Telegram${NC}"
        echo "Проверьте токен и chat_id"
    fi
}

# Функция запуска контейнеров
start_containers() {
    echo -e "\n${YELLOW}Запуск Docker контейнеров...${NC}"
    
    cd "$PROJECT_DIR"
    docker compose up -d
    
    echo -e "${YELLOW}Ожидание запуска контейнеров...${NC}"
    sleep 10
    
    # Проверка статуса
    docker compose ps
    
    if docker compose ps | grep -q "Up"; then
        echo -e "${GREEN}✓ Контейнеры запущены${NC}"
    else
        echo -e "${RED}✗ Ошибка запуска контейнеров${NC}"
        docker compose logs
        exit 1
    fi
}

# Функция вывода итоговой информации
print_summary() {
    echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   Инициализация завершена успешно!     ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"
    
    echo -e "${BLUE}Следующие шаги:${NC}"
    echo -e "1. Создайте DNS записи для ваших доменов"
    echo -e "2. Добавьте сервисы командой:"
    echo -e "   ${YELLOW}bash $PROJECT_DIR/scripts/add-service.sh${NC}"
    echo -e "3. Настройте IP-фильтрацию для БД через UFW:"
    echo -e "   ${YELLOW}ufw delete allow 5432/tcp${NC}"
    echo -e "   ${YELLOW}ufw allow from <IP>/24 to any port 5432 proto tcp${NC}"
    
    echo -e "\n${BLUE}Полезные команды:${NC}"
    echo -e "  Статус:     ${YELLOW}systemctl status balancer${NC}"
    echo -e "  Логи:       ${YELLOW}docker compose logs -f${NC}"
    echo -e "  Перезапуск: ${YELLOW}systemctl restart balancer${NC}"
    
    echo -e "\n${BLUE}Документация: ${YELLOW}$PROJECT_DIR/README.md${NC}\n"
}

# Основная функция
main() {
    check_dependencies
    collect_configuration
    create_directory_structure
    create_env_file
    create_self_signed_cert
    setup_firewall
    setup_fail2ban
    create_systemd_service
    start_containers
    test_telegram
    print_summary
}

# Запуск
main
```

### 6.2 Скрипт добавления сервиса

```bash
#!/bin/bash
