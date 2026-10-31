"""API de la tienda: productos (con caché en Redis) y pedidos (en PostgreSQL)."""

import json
import os
from contextlib import asynccontextmanager
from urllib.parse import quote

import redis
from fastapi import FastAPI, HTTPException
from psycopg_pool import ConnectionPool
from pydantic import BaseModel, Field


def database_url() -> str:
    """DATABASE_URL completa (Compose, CI) o por piezas (AWS: la contraseña la inyecta ECS desde el
    secreto que gestiona y rota RDS, que es un JSON y no una URL)."""
    if url := os.environ.get("DATABASE_URL"):
        return url
    usuario = quote(os.environ["DB_USER"], safe="")
    clave = quote(os.environ["DB_PASSWORD"], safe="")
    host = os.environ["DB_HOST"]
    puerto = os.environ.get("DB_PORT", "5432")
    nombre = os.environ.get("DB_NAME", "app")
    ssl = os.environ.get("DB_SSLMODE", "require")
    return f"postgresql://{usuario}:{clave}@{host}:{puerto}/{nombre}?sslmode={ssl}"


DATABASE_URL = database_url()
REDIS_URL = os.environ.get("REDIS_URL", "redis://cache:6379/0")
VERSION = os.environ.get("APP_VERSION", "dev")

pool = ConnectionPool(DATABASE_URL, min_size=1, max_size=5, open=False)
cache = redis.Redis.from_url(REDIS_URL, socket_timeout=1, decode_responses=True)

ESQUEMA = """
CREATE TABLE IF NOT EXISTS productos (
    id     SERIAL PRIMARY KEY,
    nombre TEXT NOT NULL UNIQUE,
    precio NUMERIC(10, 2) NOT NULL,
    stock  INT NOT NULL CHECK (stock >= 0)
);
CREATE TABLE IF NOT EXISTS pedidos (
    id          SERIAL PRIMARY KEY,
    producto_id INT NOT NULL REFERENCES productos (id),
    cantidad    INT NOT NULL CHECK (cantidad > 0),
    creado      TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO productos (nombre, precio, stock) VALUES
    ('Camiseta DevOps', 19.90, 100),
    ('Taza "It''s always DNS"', 9.50, 50),
    ('Pegatinas Kubernetes', 3.00, 500)
ON CONFLICT (nombre) DO NOTHING;
"""


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Espera a la base de datos (hasta 30 s) y crea el esquema si no existe
    pool.open(wait=True, timeout=30)
    with pool.connection() as conn:
        conn.execute(ESQUEMA)
    yield
    pool.close()


app = FastAPI(title="Tienda API", version=VERSION, lifespan=lifespan)


class Pedido(BaseModel):
    producto_id: int
    cantidad: int = Field(gt=0, le=100)


@app.get("/health")
def health():
    with pool.connection() as conn:
        conn.execute("SELECT 1")
    return {"status": "ok", "version": VERSION}


@app.get("/api/productos")
def productos():
    try:
        guardado = cache.get("productos")
        if guardado:
            return {"origen": "cache", "productos": json.loads(guardado)}
    except redis.RedisError:
        pass  # sin caché la tienda sigue funcionando, solo más lenta
    with pool.connection() as conn:
        filas = conn.execute("SELECT id, nombre, precio::float, stock FROM productos ORDER BY id").fetchall()
    datos = [{"id": i, "nombre": n, "precio": p, "stock": s} for i, n, p, s in filas]
    try:
        cache.setex("productos", 30, json.dumps(datos))
    except redis.RedisError:
        pass
    return {"origen": "base de datos", "productos": datos}


@app.post("/api/pedidos", status_code=201)
def crear_pedido(pedido: Pedido):
    with pool.connection() as conn, conn.transaction():
        fila = conn.execute(
            "UPDATE productos SET stock = stock - %s WHERE id = %s AND stock >= %s RETURNING stock",
            (pedido.cantidad, pedido.producto_id, pedido.cantidad),
        ).fetchone()
        if fila is None:
            raise HTTPException(409, "Producto inexistente o sin stock suficiente")
        nuevo = conn.execute(
            "INSERT INTO pedidos (producto_id, cantidad) VALUES (%s, %s) RETURNING id",
            (pedido.producto_id, pedido.cantidad),
        ).fetchone()
    try:
        cache.delete("productos")
    except redis.RedisError:
        pass
    return {"id": nuevo[0], "stock_restante": fila[0]}


@app.get("/api/pedidos")
def total_pedidos():
    with pool.connection() as conn:
        total = conn.execute("SELECT count(*) FROM pedidos").fetchone()[0]
    return {"total": total}
