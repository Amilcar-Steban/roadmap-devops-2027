# Casos de prueba de las reglas (semgrep --test): "ruleid" debe detectarse, "ok" no.
import os


def buscar_inseguro(conn, nombre):
    # ruleid: sql-construido-con-texto
    conn.execute(f"SELECT * FROM productos WHERE nombre = '{nombre}'")
    # ruleid: sql-construido-con-texto
    conn.execute("SELECT * FROM productos WHERE nombre = '" + nombre + "'")
    # ruleid: sql-construido-con-texto
    conn.execute("SELECT * FROM productos WHERE id = %s" % nombre)


def buscar_seguro(conn, nombre):
    # ok: sql-construido-con-texto
    conn.execute("SELECT * FROM productos WHERE nombre = %s", (nombre,))


# ruleid: secreto-en-el-codigo
DB_PASSWORD = "s3cr3t-de-produccion"  # gitleaks:allow (secreto falso: caso de prueba de la regla)
# ok: secreto-en-el-codigo
DB_PASSWORD_DESDE_ENTORNO = os.environ.get("DB_PASSWORD", "")
# ok: secreto-en-el-codigo
nombre_tabla = "productos"


def cobrar(pasarela, pedido):
    # ruleid: excepcion-silenciada
    try:
        pasarela.cobrar(pedido)
    except Exception:
        pass
