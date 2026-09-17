#!/usr/bin/env bash
# Переносит ключ сервисного аккаунта Firebase в .env.production на сервере.
#
#   ./scripts/set-fcm-env.sh ~/Downloads/имя-скачанного-файла.json
#
# Приватный ключ нигде не печатается: он читается из JSON, кодируется в base64
# и уходит на сервер по ssh. Сам файл остаётся у вас — после успеха его лучше
# удалить, а при утечке отозвать ключ в консоли Firebase.
set -euo pipefail

JSON="${1:-}"
if [ -z "$JSON" ] || [ ! -f "$JSON" ]; then
  echo "Не нашёл файл: ${JSON:-(путь не указан)}" >&2
  echo >&2
  echo "Нужен JSON ключа сервисного аккаунта из Firebase Console:" >&2
  echo "  Project settings -> Service accounts -> Generate new private key" >&2
  echo >&2
  FOUND=$(ls -t "$HOME"/Downloads/*firebase-adminsdk*.json 2>/dev/null | head -3)
  if [ -n "$FOUND" ]; then
    echo "Похоже, он у вас уже скачан:" >&2
    echo "$FOUND" | sed 's|^|  |' >&2
    echo >&2
    echo "Тогда запустите так:" >&2
    echo "  $0 $(echo "$FOUND" | head -1)" >&2
  else
    echo "Использование: $0 <путь-к-json>" >&2
  fi
  exit 1
fi

HOST="matvey@51.250.27.103"
KEY="/Users/matvey/Downloads/ssh-key-1778488290689/ssh-key-1778488290689"
RELEASE="${RELEASE:-20260917-android-push}"
ENV_FILE="/opt/tennis-search/releases/$RELEASE/.env.production"

read -r PROJECT_ID CLIENT_EMAIL PRIVATE_KEY_B64 <<EOF
$(python3 - "$JSON" <<'PY'
import base64, json, sys
d = json.load(open(sys.argv[1]))
for field in ("project_id", "client_email", "private_key"):
    if not d.get(field):
        sys.exit(f"В JSON нет поля {field} — это точно ключ сервисного аккаунта?")
print(d["project_id"], d["client_email"], base64.b64encode(d["private_key"].encode()).decode())
PY
)
EOF

echo "Проект : $PROJECT_ID"
echo "Аккаунт: $CLIENT_EMAIL"
echo "Ключ   : закодирован, ${#PRIVATE_KEY_B64} символов"

ssh -o IdentitiesOnly=yes -o ConnectTimeout=60 -i "$KEY" "$HOST" \
  "FILE='$ENV_FILE'; \
   cp \"\$FILE\" \"\$FILE.bak\"; \
   sed -i '/^FCM_PROJECT_ID=/d; /^FCM_CLIENT_EMAIL=/d; /^FCM_PRIVATE_KEY=/d' \"\$FILE\"; \
   printf '\n# Firebase: ключ сервисного аккаунта для отправки пушей на Android\nFCM_PROJECT_ID=%s\nFCM_CLIENT_EMAIL=%s\nFCM_PRIVATE_KEY=%s\n' \
     '$PROJECT_ID' '$CLIENT_EMAIL' '$PRIVATE_KEY_B64' >> \"\$FILE\"; \
   echo \"записано, строк в файле: \$(grep -c . \"\$FILE\")\""

echo
echo "Готово. Перезапустите приложение, чтобы оно прочитало новые переменные:"
echo "  ssh -o IdentitiesOnly=yes -i $KEY $HOST 'cd /opt/tennis-search/releases/$RELEASE && docker compose -p tennis-search --env-file .env.production -f docker-compose.prod.yml up -d'"
