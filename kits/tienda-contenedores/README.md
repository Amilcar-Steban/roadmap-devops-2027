# Tienda en contenedores

Proyecto final de la Fase 1 del Roadmap DevOps 2027: una aplicación de tres capas
(frontend, API y PostgreSQL con caché en Redis) con imágenes optimizadas y
seguras, orquestada con Docker Compose.

```
navegador → proxy (nginx sin root, 127.0.0.1:8080) ─┬→ frontend (nginx sin root)
                                                     └→ api (FastAPI, sin root) ─┬→ db (PostgreSQL 17, volumen)
                                                                                 └→ cache (Redis, sin disco)
```

## Arrancar en desarrollo

Funciona igual en Windows (Docker Desktop o WSL), macOS y Linux:

```bash
cp .env.example .env            # cambia DB_PASSWORD
docker compose up -d --build    # aplica compose.override.yaml: recarga en caliente de la API
docker compose ps               # espera a que api y db estén healthy
./scripts/verify.sh
```

Abre http://localhost:8080. La API también responde directamente en
http://localhost:8000/docs (solo en desarrollo).

## Producción (el servidor de la Fase 0)

1. Publica las imágenes en GHCR (en tu máquina o, desde la Fase 2, en el CI):

   ```bash
   docker buildx build --platform linux/amd64,linux/arm64 --build-arg VERSION=1.0.0 \
     -t ghcr.io/TU-USUARIO/tienda-api:1.0.0 --push ./api
   docker buildx build --platform linux/amd64,linux/arm64 \
     -t ghcr.io/TU-USUARIO/tienda-frontend:1.0.0 --push ./frontend
   ```

2. En el servidor, descomenta en `.env` las variables de producción
   (`GHCR_USER`, `TAG`, `COMPOSE_FILE`) y ejecuta:

   ```bash
   docker compose pull
   docker compose up -d
   ./scripts/verify.sh --parada
   ```

3. En el Nginx del host (Fase 0), cambia `proxy_pass` de `/` a `http://127.0.0.1:8080`.

Actualizar: cambia `TAG` en `.env` y repite `pull` y `up -d`. Volver atrás: el tag anterior.

## Backups

```bash
./scripts/backup-db.sh                 # dump comprimido en backups/, conserva 7 días
gunzip -c backups/app-FECHA.sql.gz | docker compose exec -T db psql -U app -d app
```

Prográmalo con un timer de systemd en el servidor, como en la Fase 0.

## Decisiones

- Solo el proxy publica un puerto, y solo en 127.0.0.1.
- La red `backend` es `internal`: la base de datos y Redis no tienen salida a internet.
- Ningún servicio propio corre como root; en producción, además, con el sistema de
  archivos en solo lectura, sin capabilities y con `no-new-privileges`.
- Logs con el driver `local` y rotación, para que no llenen el disco.

## Qué aprendí

(Tamaño de cada imagen antes y después, resultado de Trivy, problemas que encontraste.)
