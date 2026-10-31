# Runbook de la tienda

## ApiPresupuestoConsumoRapido

**Qué significa**: en la última hora (y en los últimos 5 minutos) más del 1,44 % de las peticiones
de la API devuelve 5xx. A este ritmo, el presupuesto de error del mes se agota en unas 50 horas.
Afecta a usuarios ahora.

**Confirmar**
1. Grafana → "Tienda · API": ¿qué rutas y códigos? ¿desde cuándo? ¿coincide con un despliegue?
2. Explore → Tempo: `{ resource.service.name = "tienda-api" && status = error }`. Abre una traza: el
   span en rojo y su evento `exception` dicen qué falla (base de datos, caché, código).
3. `docker compose … ps` (o `kubectl get pods -n tienda`): ¿están sanos la API, PostgreSQL y la caché?

**Mitigar** (primero restaurar, después investigar)
- Si coincide con un despliegue: vuelve a la versión anterior (`git revert` en el repo GitOps, o
  `kubectl argo rollouts abort` si el canary sigue en curso).
- Si es la base de datos: comprueba que acepta conexiones (`pg_isready`), espacio en disco y
  conexiones abiertas; en RDS, eventos y métricas de la instancia.
- Si es la caché: la API debería degradarse sin ella; si no lo hace, es un fallo a corregir.

**Escalar**: si no se mitiga en 15 minutos, declara un incidente SEV2 (Fase 7, módulo 12).

## ApiPresupuestoConsumoSostenido

Lo mismo con menos urgencia: más del 0,6 % de errores sostenido durante horas. Investiga en horario
laboral; si se mantiene, consumirá el 5 % del presupuesto cada 6 horas.

## ApiSinTrafico

No llegan peticiones (o no llegan sus métricas). Comprueba primero el Collector
(`up{job="collector"}`), después el proxy y la API. Si el Collector está caído, esta alerta se
inhibe y salta `CollectorCaido`.

## CollectorCaido

El OpenTelemetry Collector no responde: no llega telemetría y todas las demás alertas están ciegas.
Revisa sus logs (`docker compose … logs collector`) y su configuración
(`otelcol-contrib validate --config=…`).
