# 8. Примеры использования

## 8. Примеры использования

### 8.1 Добавление React приложения (Static)

```bash
# На сервере
cd /opt/balancer
sudo bash scripts/add-service.sh

# Ввод:
# Имя: myapp
# Поддомен: app
# Домен: example.ru
# Категория: 2 (Frontend Static)
# 
# Результат: https://app.example.ru готов
# Директория: /opt/balancer/static/myapp/

# На локальной машине разработчика
cd my-react-app
npm run build

# Деплой
rsync -av --delete dist/ user@server:/opt/balancer/static/myapp/

# Или через скрипт на сервере
bash /opt/balancer/scripts/deploy-frontend.sh myapp ./dist
```

### 8.2 Добавление FastAPI бэкенда

```bash
sudo bash scripts/add-service.sh

# Ввод:
# Имя: api
# Поддомен: api
# Домен: example.ru
# Категория: 1 (Backend API)
# Тип: 1 (FastAPI)
# Контейнер: fastapi-app
# Порт: 8000
```

### 8.3 Добавление Next.js (SSR)

```bash
sudo bash scripts/add-service.sh

# Ввод:
# Имя: webapp
# Поддомен: www
# Домен: example.ru
# Категория: 3 (Frontend Container)
# Контейнер: nextjs-app
# Порт: 3000
```

### 8.4 Мониторинг статики

```bash
# Проверка версии
curl https://app.example.ru/.version

# Проверка cache headers
curl -I https://app.example.ru/assets/main.js

# Размер директории
du -sh /opt/balancer/static/myapp/

# Список версий
ls -lh /opt/balancer/deployments/myapp/
```

---

