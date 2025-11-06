# 3. Типы подключения сервисов

## 3. Типы подключения сервисов

### 3.1 Классификация

```mermaid
flowchart TD
    Start([Добавление сервиса]) --> Type{Тип сервиса?}
    
    Type -->|Backend API| ProxyBackend[Proxy Backend]
    ProxyBackend --> ProxyConf[Создать конфиг в<br/>conf.d/proxy/]
    ProxyConf --> SSL1[Получить SSL]
    
    Type -->|Frontend Static| SubType{Подтип<br/>Frontend?}
    
    SubType -->|Direct Mount| DirectStatic[Direct Static Mount]
    DirectStatic --> CreateDir[Создать /static/name/]
    CreateDir --> StaticConf[Создать конфиг в<br/>conf.d/static/]
    StaticConf --> SSL2[Получить SSL]
    
    SubType -->|SSR/Complex| ProxyFrontend[Proxy Frontend Container]
    ProxyFrontend --> ExternalConf[Создать конфиг в<br/>conf.d/external/]
    ExternalConf --> SSL3[Получить SSL]
    
    Type -->|Database TCP| StreamConf[Добавить в streams.conf]
    StreamConf --> UFWRule[Настроить UFW]
    
    SSL1 --> Reload[nginx -s reload]
    SSL2 --> Reload
    SSL3 --> Reload
    UFWRule --> Reload
    
    Reload --> Success([Готово])
    
    style Start fill:#4CAF50,stroke:#388E3C,color:#fff
    style Success fill:#4CAF50,stroke:#388E3C,color:#fff
    style ProxyBackend fill:#FF9800,stroke:#F57C00,color:#fff
    style DirectStatic fill:#2196F3,stroke:#1976D2,color:#fff
    style ProxyFrontend fill:#9C27B0,stroke:#7B1FA2,color:#fff
    style StreamConf fill:#F44336,stroke:#D32F2F,color:#fff
```

### 3.2 Когда использовать каждый тип

| Тип | Использовать когда | Примеры |
|-----|-------------------|---------|
| **Proxy Backend** | API, динамический контент | FastAPI, Django REST, Node.js API |
| **Direct Static** | Статический билд, SPA | React build, Vue build, Angular dist |
| **Proxy Frontend Container** | SSR, сложная логика, кастомный nginx | Next.js, Nuxt.js, custom nginx configs |
| **TCP Stream** | Базы данных | PostgreSQL, MySQL, MongoDB, CouchDB |

---

[◀ Назад к оглавлению](INDEX.md) | [Следующий раздел ▶](104_direct-mount-configs.md)
