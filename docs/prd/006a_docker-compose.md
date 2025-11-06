# 5.1 Docker Compose

## 5. Конфигурации

### 5.1 Docker Compose

```yaml
# /opt/balancer/docker-compose.yml
version: '3.8'

networks:
  proxy_network:
    name: proxy_network
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
  
  internal_network:
    name: internal_network
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 172.22.0.0/16

volumes:
  certbot_conf:
    name: certbot_conf
    driver: local
  certbot_www:
    name: certbot_www
    driver: local
  nginx_cache:
    name: nginx_cache
    driver: local

services:
  nginx:
    image: nginx:1.25-alpine
    container_name: nginx-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "5432:5432"   # PostgreSQL
      - "5984:5984"   # CouchDB
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/snippets:/etc/nginx/snippets:ro
      - ./nginx/html:/usr/share/nginx/html:ro
      - certbot_conf:/etc/letsencrypt:ro
      - certbot_www:/var/www/certbot:ro
      - nginx_cache:/var/cache/nginx
      - ./logs/nginx:/var/log/nginx
    networks:
      - proxy_network
      - internal_network
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 5s
    labels:
      - "com.balancer.description=Nginx Reverse Proxy"
      - "com.balancer.version=1.0"

  certbot:
    image: certbot/certbot:latest
    container_name: certbot
    restart: unless-stopped
    volumes:
      - certbot_conf:/etc/letsencrypt
      - certbot_www:/var/www/certbot
      - ./logs/certbot:/var/log/letsencrypt
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew --webroot -w /var/www/certbot --quiet --deploy-hook \"nginx -s reload\"; sleep 12h & wait $${!}; done;'"
    depends_on:
      nginx:
        condition: service_healthy
    networks:
      - proxy_network
    labels:
      - "com.balancer.description=SSL Certificate Manager"

  healthcheck:
    build: 
      context: ./healthcheck
      dockerfile: Dockerfile
    container_name: healthcheck-monitor
    restart: unless-stopped
    volumes:
      - ./scripts:/scripts:ro
      - certbot_conf:/etc/letsencrypt:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./logs:/logs
    environment:
      - TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
      - TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}
      - CHECK_INTERVAL=300
      - TZ=${TZ:-Europe/Moscow}
    networks:
      - proxy_network
    depends_on:
      nginx:
        condition: service_healthy
    labels:
      - "com.balancer.description=Health Monitor"
```

### 5.2 Nginx главный конфиг

```nginx
