#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/tennis-search}"
BACKUP_DIR="${BACKUP_DIR:-${PROJECT_DIR}/backups}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

mkdir -p "$BACKUP_DIR"
cd "$PROJECT_DIR"

set -a
source .env.production
set +a

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_path="${BACKUP_DIR}/tennis_search_${timestamp}.sql.gz"

docker compose -f "$COMPOSE_FILE" exec -T db pg_dump \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  --no-owner \
  --no-acl \
  | gzip > "$backup_path"

find "$BACKUP_DIR" -type f -name 'tennis_search_*.sql.gz' -mtime "+${RETENTION_DAYS}" -delete

echo "Backup written: $backup_path"
