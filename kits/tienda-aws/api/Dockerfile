# syntax=docker/dockerfile:1
# Etapas: base (común) → build (dependencias) → dev (recarga en caliente) → runtime (producción)

FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
WORKDIR /app
# Usuario sin privilegios, también en desarrollo
RUN useradd --system --uid 10001 --no-create-home app

FROM base AS build
RUN python -m venv /venv
ENV PATH=/venv/bin:$PATH
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt

FROM base AS dev
COPY --from=build /venv /venv
ENV PATH=/venv/bin:$PATH
COPY app/ ./app/
USER 10001:10001
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]

FROM base AS runtime
ARG VERSION=dev
ARG GIT_SHA=unknown
LABEL org.opencontainers.image.title="tienda-api" \
      org.opencontainers.image.version="$VERSION" \
      org.opencontainers.image.revision="$GIT_SHA"
COPY --from=build /venv /venv
ENV PATH=/venv/bin:$PATH \
    APP_VERSION=$VERSION
COPY app/ ./app/
USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]
# Forma exec: uvicorn es el PID 1 y recibe SIGTERM para un apagado limpio
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
