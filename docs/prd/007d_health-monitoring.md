# 6.4 Health Check скрипт

# /opt/balancer/scripts/health-check.sh

LOG_FILE="/logs/health-check.log"
NGINX_CONF_DIR="/etc/nginx/conf.d"
CERTBOT_CONF_DIR="/etc/letsencrypt"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

send_alert() {
    bash /scripts/telegram-alert.sh "$1" 2>/dev/null || true
}

# Проверка Nginx
check_nginx() {
    if ! nginx -t > /dev/null 2>&1; then
        send_alert "⚠️ Nginx configuration test failed!"
        log "✗ Nginx config failed"
        return 1
    fi
    
    if ! pgrep -x nginx > /dev/null; then
        send_alert "🚨 Nginx process not running!"
        log "✗ Nginx not running"
        return 1
    fi
    
    log "✓ Nginx healthy"
    return 0
}

# Проверка сертификатов
check_certificates() {
    local warning_days=30
    local now=$(date +%s)
    local alerts=()
    
    for cert_dir in "$CERTBOT_CONF_DIR/live"/*; do
        if [ -d "$cert_dir" ] && [ "$(basename "$cert_dir")" != "README" ]; then
            local domain=$(basename "$cert_dir")
            local cert_file="$cert_dir/fullchain.pem"
            
            if [ -f "$cert_file" ]; then
                local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                if [ -n "$expiry_date" ]; then
                    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null)
                    local days_left=$(( ($expiry_epoch - $now) / 86400 ))
                    
                    if [ $days_left -lt 0 ]; then
                        alerts+=("❌ Сертификат ИСТЕК: $domain")
                        log "✗ Certificate expired: $domain"
                    elif [ $days_left -lt $warning_days ]; then
                        alerts+=("⚠️ Сертификат истекает: $domain ($days_left дней)")
                        log "⚠ Certificate expiring: $domain ($days_left days)"
                    else
                        log "✓ Certificate OK: $domain ($days_left days)"
                    fi
                fi
            fi
        fi
    done
    
    if [ ${#alerts[@]} -gt 0 ]; then
        local message=$(IFS=$'\n'; echo "${alerts[*]}")
        send_alert "$message"
    fi
}

# Проверка сервисов
check_services() {
    local failed_services=()
    
    for conf_file in "$NGINX_CONF_DIR"/*.conf; do
        if [ -f "$conf_file" ] && [[ "$(basename "$conf_file")" != "default.conf" ]] && [[ "$(basename "$conf_file")" != "streams.conf" ]]; then
            local domain=$(grep -oP 'server_name\s+\K[^;]+' "$conf_file" 2>/dev/null | head -1 | tr -d ' ')
            
            if [ -n "$domain" ]; then
                local response=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$domain" --max-time 10 --connect-timeout 5 2>/dev/null || echo "000")
                
                if [ "$response" == "000" ]; then
                    failed_services+=("❌ Недоступен: $domain")
                    log "✗ Service unreachable: $domain"
                elif [ "$response" -ge 500 ]; then
                    failed_services+=("⚠️ Ошибка сервера: $domain (HTTP $response)")
                    log "✗ Service error: $domain (HTTP $response)"
                else
                    log "✓ Service OK: $domain (HTTP $response)"
                fi
            fi
        fi
    done
    
    if [ ${#failed_services[@]} -gt 0 ]; then
        local message=$(IFS=$'\n'; echo "${failed_services[*]}")
        send_alert "$message"
    fi
}

# Проверка диска
check_disk_space() {
    local threshold=90
    local usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$usage" -gt "$threshold" ]; then
        send_alert "💾 Критично мало места на диске: ${usage}%"
        log "✗ Disk space critical: ${usage}%"
    else
        log "✓ Disk space OK: ${usage}%"
    fi
}

# Основная функция
main() {
    log "=== Health check started ==="
    
    check_nginx
    check_certificates
    check_services
    check_disk_space
    
    log "=== Health check completed ==="
}

main
```

### 6.5 Telegram Alert скрипт

```bash
#!/bin/bash
