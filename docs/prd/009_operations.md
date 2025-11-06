# 8. Эксплуатация

## 8. Эксплуатация

### 8.1 Управление системой

```bash
# Статус сервиса
sudo systemctl status balancer

# Перезапуск
sudo systemctl restart balancer

# Просмотр логов
sudo docker compose -f /opt/balancer/docker-compose.yml logs -f

# Перезагрузка Nginx без downtime
sudo docker exec nginx-proxy nginx -s reload
```

### 8.2 Работа с сервисами

#### Добавление сервиса
```bash
sudo bash /opt/balancer/scripts/add-service.sh
```

#### Удаление сервиса
```bash
sudo bash /opt/balancer/scripts/remove-service.sh
```

#### Проверка конфигурации
```bash
sudo docker exec nginx-proxy nginx -t
```

### 8.3 Работа с SSL сертификатами

#### Ручное обновление
```bash
# Обновить все сертификаты
sudo docker compose -f /opt/balancer/docker-compose.yml run --rm certbot renew

# Обновить конкретный домен
sudo docker compose -f /opt/balancer/docker-compose.yml run --rm certbot \
    renew --cert-name api.example.ru
```

#### Проверка сертификата
```bash
sudo openssl x509 -in /opt/balancer/certbot/conf/live/api.example.ru/fullchain.pem -text -noout
```

### 8.4 Мониторинг логов

```bash
# Общий access лог
sudo tail -f /opt/balancer/logs/nginx/access.log

# Логи ошибок
sudo tail -f /opt/balancer/logs/nginx/error.log

# Логи конкретного сервиса
sudo tail -f /opt/balancer/logs/nginx/myapi-access.log

# Health check лог
sudo tail -f /opt/balancer/logs/health-check.log

# Stream (TCP) логи
sudo tail -f /opt/balancer/logs/nginx/stream-access.log
```

### 8.5 Анализ логов

```bash
# Топ IP адресов
awk '{print $1}' /opt/balancer/logs/nginx/access.log | sort | uniq -c | sort -nr | head -20

# Топ URL
awk '{print $7}' /opt/balancer/logs/nginx/access.log | sort | uniq -c | sort -nr | head -20

# Статистика HTTP кодов
awk '{print $9}' /opt/balancer/logs/nginx/access.log | sort | uniq -c | sort -nr

# Среднее время ответа
awk '{if($NF ~ /rt=/) {split($NF,a,"="); sum+=a[2]; count++}} END {print sum/count}' \
    /opt/balancer/logs/nginx/access.log
```

### 8.6 Настройка IP-фильтрации

#### Для HTTP/HTTPS сервиса
```bash
# Отредактировать конфиг сервиса
sudo vim /opt/balancer/nginx/conf.d/myservice.conf

# Раскомментировать и настроить
# allow 192.168.1.0/24;
# allow 10.0.0.0/8;
# deny all;

# Перезагрузить Nginx
sudo docker exec nginx-proxy nginx -t && sudo docker exec nginx-proxy nginx -s reload
```

#### Для TCP сервиса (через UFW)
```bash
# Удалить общее правило
sudo ufw delete allow 5432/tcp

# Добавить ограничение по IP
sudo ufw allow from 192.168.1.0/24 to any port 5432 proto tcp comment 'PostgreSQL'

# Проверить
sudo ufw status numbered
```

---

[◀ Назад к оглавлению](INDEX.md) | [Следующий раздел ▶](010_troubleshooting.md)
