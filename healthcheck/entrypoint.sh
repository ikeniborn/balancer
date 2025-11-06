#!/bin/bash

CHECK_INTERVAL=${CHECK_INTERVAL:-300}

echo "Health Monitor started (interval: ${CHECK_INTERVAL}s)"
echo "Telegram notifications: $([ -n "$TELEGRAM_BOT_TOKEN" ] && echo "enabled" || echo "disabled")"

while true; do
    bash /scripts/health-check.sh
    sleep $CHECK_INTERVAL
done
