#!/usr/bin/env bash
# Lista de verificación del proyecto, automatizada. Uso: sudo ./scripts/verify.sh
set -uo pipefail
correctas=0; fallidas=0
pasa()  { printf '  \033[32mOK\033[0m     %s\n' "$1"; correctas=$((correctas + 1)); }
falla() { printf '  \033[31mFALLO\033[0m  %s\n' "$1"; fallidas=$((fallidas + 1)); }
comprueba() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then pasa "$desc"; else falla "$desc"; fi; }

sin_password()     { sshd -T | grep -qx 'passwordauthentication no'; }
sin_root()         { sshd -T | grep -qx 'permitrootlogin no'; }
ufw_activo()       { ufw status verbose | grep -q 'Status: active' && ufw status verbose | grep -q 'deny (incoming)'; }
api_local()        { ss -tlnH 'sport = :8080' | grep -q '127.0.0.1:8080'; }
hay_backup()       { compgen -G '/backups/*/*.tar.gz' >/dev/null; }
auto_updates()     { grep -q 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades; }
puertos_externos() { ss -tlnH | awk '{print $4}' | grep -vE '^(127\.|\[::1\])' | grep -vE ':(22|80|443)$' || true; }

echo "SSH y red"
comprueba "sshd no acepta contraseñas"            sin_password
comprueba "root no puede entrar por SSH"          sin_root
comprueba "ufw activo y deniega la entrada"       ufw_activo
extra="$(puertos_externos | tr '\n' ' ')"
if [[ -z "$extra" ]]; then pasa "solo 22, 80 y 443 expuestos hacia fuera"; else falla "puertos expuestos de más: $extra"; fi

echo "Servicios"
comprueba "miapp activa"                          systemctl is-active --quiet miapp
comprueba "la API escucha solo en 127.0.0.1:8080" api_local
comprueba "la API responde"                       curl -fsS --max-time 5 http://127.0.0.1:8080/api/health
comprueba "configuración de Nginx válida"         nginx -t
comprueba "Nginx responde en el puerto 80"        curl -sS --max-time 5 -o /dev/null http://127.0.0.1/

echo "Operación"
comprueba "health.timer programado"               systemctl is-active --quiet health.timer
comprueba "backup.timer programado"               systemctl is-active --quiet backup.timer
comprueba "existe al menos un backup"             hay_backup
comprueba "actualizaciones automáticas activas"   auto_updates

echo
echo "Resultado: $correctas correctas, $fallidas fallidas"
(( fallidas == 0 ))
