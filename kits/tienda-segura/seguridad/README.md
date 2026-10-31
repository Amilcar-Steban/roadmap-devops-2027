# Seguridad de la tienda (Fase 8)

| Carpeta / archivo | Qué hace | Cuándo actúa |
|---|---|---|
| `semgrep/tienda.yaml` | SAST con reglas propias (SQL construido con texto, secretos, excepciones silenciadas) | Cada PR (workflow Seguridad) |
| `kyverno/cargas-seguras.yaml` | `ValidatingPolicy`: registro propio, sin `:latest`, requests obligatorios | Al crear pods en los namespaces de la tienda |
| `kyverno/imagenes-firmadas.yaml` | `ImageValidatingPolicy`: firma keyless de nuestro CI y SBOM firmado | Al crear pods con imágenes de la tienda |
| `kyverno/pruebas/` | Casos de prueba de las políticas | Cada PR (`kyverno test`) |
| `falco/reglas-tienda.yaml` | Shell en un contenedor, binarios modificados, conexiones salientes inesperadas | En ejecución |
| `openbao/postgres-desde-openbao.yaml` | Deja a OpenBao llegar a PostgreSQL para emitir credenciales dinámicas | Con OpenBao/Vault en el clúster |
| `../docs/modelo-amenazas.md` | Modelo de amenazas STRIDE que justifica cada control | Al cambiar la arquitectura |
| `../.github/workflows/image.yml` | Firma la imagen por digest y adjunta su SBOM firmado | Cada imagen publicada |

Antes de nada, pon tu usuario de GitHub (el registro de imágenes va en minúsculas, la identidad de
firma tal como aparece en GitHub):

```bash
grep -rl 'tu-usuario\|TU-USUARIO' seguridad | xargs sed -i.bak -e 's#tu-usuario#tu-usuario-en-minusculas#g' \
  -e 's#TU-USUARIO#Tu-Usuario#g' && find seguridad -name '*.bak' -delete
```

## Probar en local

```bash
semgrep --test seguridad/semgrep/                                       # reglas propias
semgrep scan --config p/python --config seguridad/semgrep/tienda.yaml api/
docker run --rm -v "$PWD/seguridad/kyverno":/k ghcr.io/kyverno/kyverno-cli:v1.19.2 test /k/pruebas
docker run --rm -v "$PWD/seguridad/falco":/r falcosecurity/falco:0.45.2 \
  falco -V /etc/falco/falco_rules.yaml -V /r/reglas-tienda.yaml
```

## Verificar una imagen publicada

```bash
IMG=ghcr.io/tu-usuario/tienda-api:X.Y.Z   # una versión que tu workflow Imagen haya publicado
cosign verify "$IMG" \
  --certificate-identity https://github.com/TU-USUARIO/tienda-pipeline/.github/workflows/image.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
cosign verify-attestation "$IMG" --type cyclonedx \
  --certificate-identity https://github.com/TU-USUARIO/tienda-pipeline/.github/workflows/image.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com > /dev/null && echo "SBOM firmado por nuestro CI"
gh attestation verify "oci://$IMG" --owner TU-USUARIO                 # procedencia SLSA
```

## En el clúster

```bash
helm install kyverno kyverno --repo https://kyverno.github.io/kyverno/ --version 3.9.2 -n kyverno --create-namespace
kubectl apply -f seguridad/kyverno/cargas-seguras.yaml -f seguridad/kyverno/imagenes-firmadas.yaml
```

Empieza con `validationActions: [Audit]` y revisa `kubectl get policyreports -A` antes de pasar a `[Deny]`.

### Falco

```bash
helm install falco falco --repo https://falcosecurity.github.io/charts --version 9.2.1 -n falco --create-namespace \
  --set driver.kind=modern_ebpf --set tty=true --set-file 'customRules.reglas-tienda\.yaml=seguridad/falco/reglas-tienda.yaml'
kubectl -n tienda exec deploy/tienda-api -- sh -c id               # → Warning "Shell en la tienda"
kubectl -n tienda exec deploy/tienda-api -- python -c \
  "import socket; s=socket.socket(); s.setblocking(False); s.connect_ex(('1.1.1.1', 443))"   # → Critical
kubectl -n falco logs ds/falco -c falco | grep -E 'Shell en la tienda|Conexión saliente'
```

Probado en kind sobre Docker Desktop (Mac ARM): la sonda `modern_ebpf` arranca en 36 s (los avisos de
`libbpf` sobre `open` y `creat` son normales en arm64, que no tiene esas llamadas). La macro `outbound`
de Falco ignora los destinos privados, así que PostgreSQL, Valkey y el Collector nunca disparan la regla
de conexiones: cualquier alerta es una conexión a Internet. Si añades reglas de diagnóstico, recuerda
que Falco solo dispara la **primera** regla que coincide con cada evento (`rule_matching: first`).

### Credenciales dinámicas con OpenBao (o Vault)

```bash
helm install openbao openbao --repo https://openbao.github.io/openbao-helm --version 0.30.6 -n secretos \
  --create-namespace --set server.dev.enabled=true --set injector.enabled=false        # solo laboratorio
kubectl apply -f seguridad/openbao/postgres-desde-openbao.yaml
```

En PostgreSQL, el usuario con el que OpenBao crea los temporales: puede crear roles y repartir los
permisos que tiene (también sobre las **secuencias**: los `id` son `SERIAL`):

```sql
CREATE ROLE vault WITH LOGIN CREATEROLE PASSWORD '…';
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO vault WITH GRANT OPTION;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO vault WITH GRANT OPTION;
```

```bash
bao secrets enable database
bao write database/config/tienda plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@postgres.tienda:5432/app?sslmode=disable" \
  allowed_roles="api" username="vault" password="…"
bao write database/roles/api db_name=tienda default_ttl=1h max_ttl=24h creation_statements='
  CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '"'"'{{password}}'"'"' VALID UNTIL '"'"'{{expiration}}'"'"';
  GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO "{{name}}";
  GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO "{{name}}";'
bao read database/creds/api                     # usuario y contraseña nuevos
bao lease revoke -prefix database/creds/api     # retira de golpe todos los emitidos
```

Lo que enseñó la prueba (OpenBao 2.7.2 y PostgreSQL 18):

- Sin el `GRANT USAGE ON ALL SEQUENCES`, crear un pedido falla: `permission denied for sequence pedidos_id_seq`.
- **La API crea su esquema al arrancar** (`CREATE TABLE IF NOT EXISTS`): con un usuario de mínimo
  privilegio no arranca (`permission denied for schema public`), aunque las tablas ya existan. Las
  migraciones deben ir aparte, con el dueño de las tablas (un Job o un hook de Helm), y la API solo
  leer y escribir datos. Darle `CREATE` sería peor: las tablas serían del usuario temporal.
- Al caducar, OpenBao revoca los permisos y borra el usuario **también para las sesiones abiertas**
  (`permission denied for table pedidos`, `invalid role OID`): una API con pool de conexiones tiene que
  renovar sus credenciales y reconectar antes de que venzan.
- La API lee la contraseña de una variable de entorno: el Agent Injector (que escribe un archivo) no le
  sirve sin cambiarla. Vault Secrets Operator o External Secrets escriben un Secret, y hay que reiniciar
  los pods cuando rota.
- La ServiceAccount de la API tiene `automountServiceAccountToken: false` (Fase 5): para el login de
  Kubernetes en OpenBao, el pod tiene que pedir el token expresamente.
