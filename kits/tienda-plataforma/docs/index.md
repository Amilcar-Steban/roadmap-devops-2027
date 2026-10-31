# La tienda

Catálogo de productos y pedidos, construida fase a fase en el Roadmap DevOps 2027.

| Dónde | Qué |
|---|---|
| [`api/`](https://github.com/TU-USUARIO/tienda-pipeline/tree/main/api) | API en FastAPI (PostgreSQL + caché) |
| [`chart/tienda`](https://github.com/TU-USUARIO/tienda-pipeline/tree/main/chart/tienda) | Chart de Helm (Fase 5) |
| [tienda-gitops](https://github.com/TU-USUARIO/tienda-gitops) | Lo que corre en cada entorno (Fase 6) |
| [`observabilidad/`](https://github.com/TU-USUARIO/tienda-pipeline/tree/main/observabilidad) | Telemetría, SLO y runbook (Fase 7) |
| [`seguridad/`](https://github.com/TU-USUARIO/tienda-pipeline/tree/main/seguridad) | SAST, políticas y firmas (Fase 8) |
| [`plataforma/`](https://github.com/TU-USUARIO/tienda-pipeline/tree/main/plataforma) | Autoservicio: bases de datos y alta de equipos (Fase 9) |

## Cómo pido…

- **Una base de datos para un servicio nuevo**: un recurso `BaseDatos` en el namespace de tu
  equipo (ver `plataforma/crossplane/ejemplo.yaml`). Llega cifrada, privada y con copias.
- **Un namespace para un equipo nuevo**: crea el namespace con las etiquetas `tipo: equipo` y
  `equipo: <nombre>`; la cuota, la política de red y los permisos aparecen solos.

## Generar esta documentación en local

```bash
docker run --rm -v "$PWD":/content -w /content --entrypoint mkdocs spotify/techdocs build --strict
```
