#!/usr/bin/env bash
# Deja una VM Ubuntu 24.04 recién creada como el servidor del proyecto.
# Idempotente: ejecutarlo varias veces produce el mismo resultado.
# Uso: sudo ./scripts/bootstrap.sh
#      sudo DOMINIO=sitio.tudominio.com EMAIL=tu@correo.com ./scripts/bootstrap.sh
set -Eeuo pipefail
trap 'echo "[bootstrap] Falló en la línea $LINENO" >&2' ERR

[[ $EUID -eq 0 ]] || { echo "Ejecuta con sudo" >&2; exit 1; }
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOMINIO="${DOMINIO:-}"
USUARIO="${SUDO_USER:-}"
log() { echo "[bootstrap] $*"; }

log "1/7 Paquetes y sistema"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q nginx ufw unattended-upgrades python3 curl certbot python3-certbot-nginx
timedatectl set-timezone UTC
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' \
  > /etc/apt/apt.conf.d/20auto-upgrades

log "2/7 Aplicación"
id miapp &>/dev/null || useradd --system --home-dir /opt/miapp --shell /usr/sbin/nologin miapp
install -d -m 755 /opt/miapp /opt/scripts /backups
install -m 644 "$REPO/app/app.py" /opt/miapp/app.py
install -m 755 "$REPO/scripts/healthcheck.sh" "$REPO/scripts/backup.sh" /opt/scripts/

log "3/7 systemd"
install -m 644 "$REPO"/systemd/*.service "$REPO"/systemd/*.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now miapp.service health.timer backup.timer
systemctl restart miapp.service

log "4/7 Nginx"
install -d -m 755 /var/www/sitio
[[ -f /var/www/sitio/index.html ]] || echo "<h1>Servidor endurecido</h1>" > /var/www/sitio/index.html
# No pisar la configuración si certbot ya le añadió HTTPS
if ! grep -q "managed by Certbot" /etc/nginx/sites-available/sitio 2>/dev/null; then
  sed "s/sitio\.tudominio\.com/${DOMINIO:-_}/" "$REPO/nginx/sitio.conf" > /etc/nginx/sites-available/sitio
fi
ln -sfn /etc/nginx/sites-available/sitio /etc/nginx/sites-enabled/sitio
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

log "5/7 SSH"
home_usuario="$(getent passwd "$USUARIO" | cut -d: -f6 || true)"
if [[ -n "$USUARIO" && -s "$home_usuario/.ssh/authorized_keys" ]]; then
  groupadd -f ssh-users
  usermod -aG ssh-users "$USUARIO"
  install -m 644 "$REPO/ssh/10-hardening.conf" /etc/ssh/sshd_config.d/10-hardening.conf
  sshd -t
  systemctl reload ssh
else
  log "AVISO: '$USUARIO' no tiene llave en authorized_keys; no endurezco SSH para no dejarte fuera"
fi

log "6/7 Firewall"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

log "7/7 TLS"
if [[ -n "$DOMINIO" && ! -d "/etc/letsencrypt/live/$DOMINIO" ]]; then
  certbot --nginx -d "$DOMINIO" -m "${EMAIL:?Define EMAIL para el certificado}" --agree-tos --redirect -n
else
  log "Sin DOMINIO o con certificado ya emitido: no se pide certificado"
fi

log "Listo. Comprueba el resultado con: sudo $REPO/scripts/verify.sh"
