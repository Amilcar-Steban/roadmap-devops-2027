#!/usr/bin/env bash
# Dump de PostgreSQL de la pila con rotación. Uso: scripts/backup-db.sh [dias_a_conservar]
# Restaurar: gunzip -c backups/app-FECHA.sql.gz | docker compose exec -T db psql -U app -d app
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

dias="${1:-7}"
mkdir -p backups
archivo="backups/app-$(date +%Y%m%d-%H%M%S).sql.gz"

docker compose exec -T db pg_dump -U app --clean --if-exists app | gzip > "$archivo.tmp"
mv "$archivo.tmp" "$archivo"
find backups -name 'app-*.sql.gz' -mtime +"$dias" -delete

echo "Backup: $archivo ($(du -h "$archivo" | cut -f1))"
