# syntax=docker/dockerfile:1
# La API de la tienda con OpenTelemetry automático, SIN tocar su código: misma app, mismas
# dependencias, más la instrumentación de FastAPI, psycopg, redis y logging. El código llega del
# directorio ../../api como contexto adicional ("codigo", ver compose.yaml).
# "runtime": compose.yaml de la tienda construye ese target, y la superposición lo hereda
FROM python:3.12-slim AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
RUN useradd --system --uid 10001 --no-create-home app && python -m venv /venv
ENV PATH=/venv/bin:$PATH
# "codigo" es un contexto adicional de BuildKit (compose.yaml), no una etapa: hadolint no lo conoce
# hadolint ignore=DL3022
COPY --from=codigo requirements.txt ./requirements.txt
COPY requirements-otel.txt ./
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt -r requirements-otel.txt \
    && opentelemetry-bootstrap --action=install  # detecta FastAPI, psycopg, redis… e instala su instrumentación
# hadolint ignore=DL3022
COPY --from=codigo app/ ./app/
# Por defecto los loggers de uvicorn no propagan al raíz, que es donde OpenTelemetry engancha su
# handler: sin esto, los errores de la API no llegarían a Loki.
COPY logging.json ./
USER 10001:10001
EXPOSE 8000
CMD ["opentelemetry-instrument", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--log-config", "logging.json"]
