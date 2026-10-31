# Servidor web endurecido

Proyecto final de la Fase 0 del Roadmap DevOps 2027: un servidor Ubuntu 24.04
listo para producción, reproducible con un solo script.

## Qué incluye

- Nginx con sitio estático, proxy a `/api/` y HTTPS con Let's Encrypt
- API Python (`app/app.py`) como servicio de systemd, solo en 127.0.0.1:8080
- SSH solo con llave, sin root, acceso por el grupo `ssh-users`
- Firewall ufw: entrada denegada salvo 22, 80 y 443
- Healthcheck cada 5 minutos y backups diarios con rotación (timers de systemd)
- Actualizaciones de seguridad automáticas

## Uso rápido (Multipass, en Windows, macOS o Linux)

```bash
multipass launch 24.04 --name web-01 --cpus 1 --memory 1G
multipass transfer --recursive servidor-endurecido web-01:/home/ubuntu/
multipass shell web-01
cd servidor-endurecido
sudo ./scripts/bootstrap.sh
sudo systemctl start backup.service   # primer backup sin esperar a las 03:00
sudo ./scripts/verify.sh
```

Con dominio propio apuntando a la IP de la VM (HTTPS con Let's Encrypt; al
ejecutarlo aceptas sus condiciones de uso):

```bash
sudo DOMINIO=sitio.tudominio.com EMAIL=tu@correo.com ./scripts/bootstrap.sh
```

## Estructura

| Ruta | Contenido |
|------|-----------|
| `app/` | API mínima con la librería estándar de Python |
| `systemd/` | units del servicio, del healthcheck y del backup |
| `nginx/` | configuración del sitio |
| `ssh/` | endurecimiento de sshd |
| `scripts/` | bootstrap, verificación, healthcheck y backup |
| `docs/` | checklist de seguridad |

## Decisiones

- La API escucha en localhost: solo Nginx la expone, y Nginx es quien termina TLS.
- Los servicios corren con usuarios sin privilegios y con el endurecimiento de systemd.
- `bootstrap.sh` no endurece SSH si tu usuario no tiene una llave en
  `authorized_keys`, para no dejarte fuera.

## Qué aprendí

(Escribe aquí tus conclusiones: qué fue difícil, qué harías distinto.)
