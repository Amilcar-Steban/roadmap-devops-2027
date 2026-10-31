# Pipeline de la tienda

Proyecto final de la Fase 2: el repositorio de la Fase 1 con CI/CD completo en GitHub Actions.

```
pull request ──► ci.yml: calidad · pruebas (PostgreSQL y Redis reales) · seguridad · build (api, frontend)
merge a main ──► image.yml: build ─► Trivy ─► push multiarch a GHCR ─► procedencia SLSA
                                └─► deploy.yml (staging) ─► smoke ─► aprobación ─► deploy.yml (produccion) ─► smoke
                 release.yml: PR de release con changelog (release-please)
```

Todas las acciones están fijadas por SHA; Dependabot (`.github/dependabot.yml`) abre PRs para actualizarlas.

## 1 · Repositorio

1. Sube este proyecto a un repositorio de GitHub y cambia `tu-usuario` en `.github/CODEOWNERS`.
2. Settings → Actions → General → Workflow permissions: **Read repository contents** y marca
   **Allow GitHub Actions to create and approve pull requests** (release-please abre un PR de release;
   sin esta casilla falla con "GitHub Actions is not permitted to create or approve pull requests").
3. Settings → Rules → New ruleset para `main`:
   - Require a pull request before merging (1 aprobación, y "Require review from Code Owners").
   - Require status checks: `calidad`, `pruebas`, `seguridad`, `build (api)`, `build (frontend)`.
   - Block force pushes.
4. En local: `pipx install pre-commit && pre-commit install`.

## 2 · Servidor (el de la Fase 0, con Docker de la Fase 1)

```bash
sudo adduser --disabled-password --gecos "" deploy
sudo usermod -aG docker deploy                 # sin sudo
sudo install -d -o deploy -g deploy /opt/tienda
sudo -u deploy git clone https://github.com/TU-USUARIO/tienda.git /opt/tienda
sudo -u deploy cp /opt/tienda/.env.example /opt/tienda/.env   # edítalo: contraseña real y variables de producción
```

En tu máquina, una llave solo para despliegues:

```bash
ssh-keygen -t ed25519 -f deploy_tienda -N "" -C "deploy tienda"
ssh-copy-id -i deploy_tienda.pub deploy@SERVIDOR
ssh-keyscan -t ed25519 SERVIDOR > known_hosts_tienda
```

Si GHCR es privado, en el servidor: `echo TOKEN | sudo -u deploy docker login ghcr.io -u TU-USUARIO --password-stdin`
(un token con solo `read:packages`).

## 3 · Entornos en GitHub

Crea los entornos `staging` y `produccion` (Settings → Environments). En cada uno:

```bash
gh secret set SSH_KEY --env staging < deploy_tienda
gh secret set KNOWN_HOSTS --env staging < known_hosts_tienda
gh variable set HOST --env staging --body "staging.tienda.ejemplo.com"
gh variable set URL --env staging --body "https://staging.tienda.ejemplo.com"
# repite con --env produccion y sus valores
```

En `produccion`, añade **Required reviewers** y limita las ramas de despliegue a `main`.
Después borra los archivos `deploy_tienda*` y `known_hosts_tienda` de tu máquina.

Por último, activa el despliegue automático (mientras no exista esta variable, `image.yml`
publica las imágenes pero no intenta desplegar):

```bash
gh variable set DEPLOY_ENABLED --body true
```

## 4 · Uso diario

- Abre un PR: `ci.yml` lo valida en unos minutos.
- Fusiónalo: `image.yml` publica `sha-1234abc` y `main`, despliega en staging y espera tu aprobación para producción.
- Versiones: release-please mantiene un PR de release; al fusionarlo crea la etiqueta `vX.Y.Z` y se publica la imagen `X.Y.Z`.
  Para que esa etiqueta dispare `image.yml`, release-please necesita el token de una GitHub App
  (los eventos creados con `GITHUB_TOKEN` no disparan otros workflows).
- Rollback: Actions → Deploy → Run workflow → entorno y etiqueta anterior. `scripts/deploy.sh` además
  vuelve solo a la versión anterior si la nueva no queda sana.

## 5 · Verificación

```bash
gh attestation verify oci://ghcr.io/TU-USUARIO/tienda-api:sha-1234abc --owner TU-USUARIO
gh run list --workflow CI --limit 10
```
