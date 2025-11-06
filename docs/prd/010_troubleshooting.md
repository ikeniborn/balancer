# 9. Troubleshooting

## 9. Troubleshooting

### 9.1 Частые проблемы и решения

#### Проблема: "502 Bad Gateway"

**Причины:**
1. Backend сервис не запущен
2. Неверное имя хоста в конфиге
3. Backend не в той же Docker сети

**Решение:**
```bash
# 1. Проверить backend
docker ps | grep backend-name
docker logs backend-name

# 2. Проверить сетевую связность
docker exec nginx-proxy ping backend-name

# 3. Проверить конфиг
grep upstream /opt/balancer/nginx/conf.d/service.conf

# 4. Проверить Docker сеть
docker network inspect proxy_network
```

#### Проблема: SSL сертификат не получается

**Причины:**
1. DNS запись не настроена
2. Порт 80 закрыт
3. Неверный email

**Решение:**
```bash
# 1. Проверить DNS
host api.example.ru

# 2. Проверить UFW
sudo ufw status | grep 80

# 3. Попробовать вручную с debug
sudo docker compose run --rm certbot certonly \
    --webroot -w /var/www/certbot \
    -d api.example.ru \
    --dry-run \
    --verbose

# 4. Проверить ACME challenge
curl http://api.example.ru/.well-known/acme-challenge/test
```

#### Проблема: High CPU/Memory usage

**Решение:**
```bash
# 1. Проверить процессы
docker stats

# 2. Проверить nginx worker processes
docker exec nginx-proxy ps aux | grep nginx

# 3. Проверить количество соединений
docker exec nginx-proxy netstat -an | grep ESTABLISHED | wc -l

# 4. Проверить логи на аномалии
sudo tail -1000 /opt/balancer/logs/nginx/access.log | \
    awk '{print $1}' | sort | uniq -c | sort -nr | head -10
```

#### Проблема: Контейнеры не запускаются

**Решение:**
```bash
# 1. Проверить логи
docker compose -f /opt/balancer/docker-compose.yml logs

# 2. Проверить порты
sudo netstat -tulpn | grep -E '80|443|5432|5984'

# 3. Пересоздать контейнеры
cd /opt/balancer
docker compose down
docker compose up -d

# 4. Проверить volumes
docker volume ls | grep balancer
```

### 9.2 Диагностические команды

```bash
# Общая проверка системы
sudo bash /opt/balancer/scripts/health-check.sh

# Проверка конфигурации Nginx
sudo docker exec nginx-proxy nginx -t

# Проверка upstream серверов
sudo docker exec nginx-proxy nginx -T | grep upstream -A 3

# Проверка SSL сертификатов
sudo docker compose run --rm certbot certificates

# Проверка Docker сетей
docker network ls
docker network inspect proxy_network

# Проверка UFW
sudo ufw status verbose

# Проверка Fail2Ban
sudo fail2ban-client status
```

### 9.3 Восстановление после сбоя

```bash
# 1. Остановить все
cd /opt/balancer
sudo docker compose down

# 2. Проверить и очистить
docker system prune -f

# 3. Проверить конфигурацию
find nginx/conf.d -name "*.conf" -exec nginx -t -c {} \;

# 4. Запустить заново
sudo docker compose up -d

# 5. Проверить логи
docker compose logs -f
```

---

[◀ Назад к оглавлению](INDEX.md) | [Следующий раздел ▶](011_appendices.md)
