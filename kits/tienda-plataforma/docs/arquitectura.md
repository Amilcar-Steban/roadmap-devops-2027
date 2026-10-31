# Arquitectura

```text
usuario ──► Gateway (Envoy) ─┬─ /      ──► frontend (Nginx)
                             └─ /api/* ──► API (FastAPI) ─┬─► PostgreSQL (RDS)
                                                           └─► Valkey (ElastiCache)
```

- **Entrega**: GitHub Actions construye, escanea, firma y publica las imágenes; Argo CD las
  despliega desde `tienda-gitops`, con canary y análisis (Argo Rollouts).
- **Seguridad**: Pod Security `restricted`, NetworkPolicies, y Kyverno solo admite imágenes
  firmadas por nuestro CI.
- **Observabilidad**: OpenTelemetry → Collector → Prometheus, Loki y Tempo; SLO del 99,9 %.
- **Datos**: la API crea su esquema al arrancar; la caché es opcional (si cae, se registra un aviso).
