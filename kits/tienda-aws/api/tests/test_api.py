"""Pruebas de la API contra PostgreSQL y Redis reales (en el CI, contenedores de servicio)."""

import os

import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("DATABASE_URL", "postgresql://app:test@localhost:5432/app")
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/0")

from app.main import app, cache  # noqa: E402  (las variables deben existir antes de importar)


@pytest.fixture(scope="module")
def client():
    # TestClient ejecuta el lifespan: abre el pool de conexiones y crea el esquema
    with TestClient(app) as c:
        cache.flushdb()
        yield c


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_productos_usa_la_cache(client):
    primero = client.get("/api/productos").json()
    segundo = client.get("/api/productos").json()
    assert primero["origen"] == "base de datos"
    assert segundo["origen"] == "cache"
    assert len(segundo["productos"]) >= 3


def test_pedido_descuenta_stock(client):
    antes = {p["id"]: p["stock"] for p in client.get("/api/productos").json()["productos"]}
    r = client.post("/api/pedidos", json={"producto_id": 1, "cantidad": 2})
    assert r.status_code == 201
    assert r.json()["stock_restante"] == antes[1] - 2


def test_pedido_sin_stock_suficiente(client):
    r = client.post("/api/pedidos", json={"producto_id": 1, "cantidad": 100})
    assert r.status_code == 409


def test_cantidad_invalida(client):
    r = client.post("/api/pedidos", json={"producto_id": 1, "cantidad": 0})
    assert r.status_code == 422


def test_database_url_por_piezas(monkeypatch):
    from app.main import database_url

    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.setenv("DB_USER", "app")
    monkeypatch.setenv("DB_PASSWORD", "p@ss:word/")
    monkeypatch.setenv("DB_HOST", "tienda.abc123.us-east-1.rds.amazonaws.com")
    assert database_url() == (
        "postgresql://app:p%40ss%3Aword%2F@tienda.abc123.us-east-1.rds.amazonaws.com:5432/app?sslmode=require"
    )
