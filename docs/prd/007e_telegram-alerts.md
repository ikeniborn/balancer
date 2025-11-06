# 6.5 Telegram Alert скрипт

# /opt/balancer/scripts/telegram-alert.sh

MESSAGE="$1"

if [ -z "$MESSAGE" ]; then
    echo "Usage: $0 \"message\""
    exit 1
fi

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo "Error: TELEGRAM credentials not set"
    exit 1
fi

HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")

FULL_MESSAGE="🖥 <b>Host:</b> $HOSTNAME%0A"
FULL_MESSAGE+="🌐 <b>IP:</b> $SERVER_IP%0A"
FULL_MESSAGE+="⏰ <b>Time:</b> $TIMESTAMP%0A%0A"
FULL_MESSAGE+="$MESSAGE"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=${FULL_MESSAGE}" \
    -d "parse_mode=HTML" \
    > /dev/null 2>&1

exit $?
```

---

[◀ Назад к оглавлению](INDEX.md) | [Следующий раздел ▶](007f_healthcheck-dockerfile.md)
