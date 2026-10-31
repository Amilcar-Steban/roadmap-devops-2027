# 0001 · Imágenes firmadas y verificadas al admitir

- **Estado**: aceptada (Fase 8)
- **Contexto**: entre el commit y el pod hay muchos eslabones (repositorio, CI, acciones de
  terceros, registro). Cualquiera comprometido podría colar una imagen alterada con la misma etiqueta.
- **Decisión**: el workflow Imagen firma cada imagen por digest con Sigstore (keyless, identidad
  OIDC del workflow) y adjunta su SBOM firmado. Kyverno (`ImageValidatingPolicy`) solo admite
  imágenes firmadas por `image.yml` en `main`, y fija el pod al digest verificado.
- **Alternativas descartadas**: firma con claves propias (hay que custodiarlas y rotarlas); solo
  procedencia SLSA sin verificación en el clúster (no impide ejecutar lo no verificado).
- **Consecuencias**: una imagen construida a mano no se puede desplegar; si Rekor o el registro no
  responden, la admisión falla (por eso el timeout del webhook es de 20 s).
