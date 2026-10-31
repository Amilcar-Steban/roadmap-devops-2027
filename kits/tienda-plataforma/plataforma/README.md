# Plataforma de la tienda (Fase 9)

Autoservicio para los equipos: piden lo que necesitan con unas líneas de YAML y la plataforma
aplica los estándares (seguridad, copias, coste) sin que nadie tenga que recordarlos.

| Archivo | Qué ofrece |
|---|---|
| `crossplane/xrd-basedatos.yaml` | La API `BaseDatos` (tamaño, versión, Multi-AZ): lo único que ve un equipo |
| `crossplane/composition-basedatos-aws.yaml` | Cómo se cumple en AWS: RDS cifrada, privada, con copias, contraseña gestionada y etiquetas de coste |
| `crossplane/funciones.yaml` y `crossplane/proveedor.yaml` | La función que ejecuta la composición y el proveedor de RDS |
| `crossplane/ejemplo.yaml` | Lo que escribe un equipo en su repositorio GitOps |
| `crossplane/laboratorio/` | Solo para probar sin AWS: el proveedor apuntando a moto, un guardarraíl de DNS y la función para `render` |
| `kyverno/alta-de-equipo.yaml` | Namespace con `tipo: equipo` → cuota, límites, red cerrada y permisos del grupo |
| `../catalog-info.yaml` | La tienda en el catálogo de Backstage (sistema, componentes, API, recursos, equipo) |
| `../mkdocs.yml` y `../docs/` | TechDocs: la documentación que Backstage publica en la página del servicio |

Cambia `TU-USUARIO` por tu usuario de GitHub en `catalog-info.yaml` y `docs/index.md` (los enlaces y
el `github.com/project-slug` que usan los plugins de GitHub):

```bash
sed -i.bak 's#TU-USUARIO#Tu-Usuario#g' catalog-info.yaml docs/index.md && rm -f catalog-info.yaml.bak docs/index.md.bak
```

## Probar en kind

```bash
kind create cluster --name plat
helm install kyverno kyverno --repo https://kyverno.github.io/kyverno/ --version 3.9.2 -n kyverno --create-namespace --wait
helm install crossplane crossplane --repo https://charts.crossplane.io/stable --version 2.4.3 -n crossplane-system --create-namespace --wait

# Alta de equipo
kubectl apply -f plataforma/kyverno/alta-de-equipo.yaml
kubectl create ns pagos && kubectl label ns pagos tipo=equipo equipo=equipo-pagos
kubectl get resourcequota,limitrange,networkpolicy,rolebinding -n pagos

# Base de datos de autoservicio (sin ProviderConfig se crea el recurso, pero no llega a ninguna nube)
kubectl apply -f plataforma/crossplane/funciones.yaml -f plataforma/crossplane/proveedor.yaml
kubectl wait providers.pkg.crossplane.io/provider-aws-rds --for=condition=Healthy --timeout=5m
kubectl apply -f plataforma/crossplane/xrd-basedatos.yaml -f plataforma/crossplane/composition-basedatos-aws.yaml
kubectl create ns notificaciones && kubectl apply -f plataforma/crossplane/ejemplo.yaml
kubectl get instances.rds.aws.m.upbound.io -n notificaciones -o yaml   # la RDS que generó la plataforma
```

Para que llegue a AWS: un `ClusterProviderConfig` con credenciales (en EKS, Pod Identity para el
proveedor) y la capa `datos` de la Fase 4, que crea el grupo de subredes `tienda-prod`.

## Probar la RDS de verdad, pero contra un simulador (moto)

Sigue al bloque anterior. **Pon primero el guardarraíl**: si el `ProviderConfig` está mal, el proveedor
llama a AWS real. En nuestra prueba pasó (sin `endpoint.services`, ignoró la URL de moto).

```bash
# 1. Guardarraíl: dentro del clúster, *.amazonaws.com no resuelve
kubectl apply -f plataforma/crossplane/laboratorio/coredns-sin-aws.yaml
kubectl -n kube-system rollout restart deploy/coredns

# 2. moto en la red de kind, y el grupo de subredes que espera la composición
docker run -d --name moto --network kind motoserver/moto:5.2.5
aws() { docker run --rm -i --network kind -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test \
  -e AWS_DEFAULT_REGION=us-east-1 amazon/aws-cli:2.31.20 --endpoint-url http://moto:5000 "$@"; }
VPC=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text)
S1=$(aws ec2 create-subnet --vpc-id $VPC --cidr-block 10.0.1.0/24 --availability-zone us-east-1a --query Subnet.SubnetId --output text)
S2=$(aws ec2 create-subnet --vpc-id $VPC --cidr-block 10.0.2.0/24 --availability-zone us-east-1b --query Subnet.SubnetId --output text)
aws rds create-db-subnet-group --db-subnet-group-name tienda-prod --db-subnet-group-description tienda --subnet-ids $S1 $S2

# 3. El proveedor habla con moto, y la base se crea en él (1-2 minutos)
kubectl apply -f plataforma/crossplane/laboratorio/moto.yaml
kubectl wait basedatos.plataforma.tienda.dev/notificaciones-db -n notificaciones --for=condition=Ready --timeout=5m
kubectl get basedatos -n notificaciones -o jsonpath='{.items[0].status}'   # endpoint y secretoArn
aws rds describe-db-instances --query 'DBInstances[].[DBInstanceClass,Engine,StorageEncrypted,DeletionProtection]'

# 4. Deriva: alguien cambia la base a mano; Crossplane la devuelve a lo declarado (en el siguiente sondeo,
#    o enseguida si fuerzas la reconciliación con una anotación)
ID=$(aws rds describe-db-instances --query 'DBInstances[0].DBInstanceIdentifier' --output text)
aws rds modify-db-instance --db-instance-identifier $ID --db-instance-class db.m7g.2xlarge --apply-immediately
kubectl annotate instances.rds.aws.m.upbound.io -n notificaciones --all prueba=$(date +%s) --overwrite
```

Limitaciones de moto: da el mismo identificador interno a todas las instancias, así que prueba **una sola**
base cada vez. Y antes de borrar el clúster, borra el `BaseDatos`: una instancia creada sin que Crossplane
la registre se queda huérfana (en AWS real, facturando).

**Retirar una base.** La composición fija `deletionProtection: true`, así que borrar el `BaseDatos` no
basta: AWS rechaza el borrado. Es intencionado. Para retirarla, la plataforma desactiva la protección
de forma explícita y después se borra; AWS deja el snapshot `<nombre>-final`.

## Validar sin clúster

```bash
docker run --rm -v "$PWD":/content -w /content --entrypoint mkdocs spotify/techdocs build --strict
docker run --rm -v "$PWD":/w -w /w node:22-alpine npx -y @roadiehq/backstage-entity-validator catalog-info.yaml

```

### Crossplane: validar y "renderizar" la composición

Desde la 2.x el CLI vive en su propio repositorio (`crossplane/cli`) y sus comandos se llaman
`crossplane resource validate` y `crossplane composition render` (antes `beta validate` y `render`). Las
releases no traen binarios con versión, así que lo compilamos fijado y lo usamos dentro de un contenedor:

```bash
# Desde plataforma/crossplane. El CLI (Linux) se compila una vez: 2 minutos, 136 MB
mkdir -p bin && docker run --rm -v "$PWD/bin":/go/bin -e CGO_ENABLED=0 golang:1.26 \
  go install github.com/crossplane/cli/v2/cmd/crossplane@v2.4.1
# El motor que usa "render", sacado de la imagen fijada de Crossplane (así no necesita Docker)
docker create --name xp-core xpkg.crossplane.io/crossplane/crossplane:v2.4.3 \
  && docker cp -L xp-core:/bin/crossplane bin/crossplane-core && docker rm xp-core

docker network create xp
xp() { docker run --rm --network xp -v "$PWD":/w -w /w -e HOME=/w/.cache alpine:3.22.2 bin/crossplane "$@"; }

# 1. Validar el ejemplo contra la API, y la composición (con la entrada de su función) contra sus esquemas
xp resource validate --crossplane-image=xpkg.crossplane.io/crossplane/crossplane:v2.4.3 \
  xrd-basedatos.yaml,proveedor.yaml,funciones.yaml ejemplo.yaml,composition-basedatos-aws.yaml

# 2. Renderizar: la RDS que generaría la plataforma, sin clúster ni socket de Docker
docker run -d --rm --name fn-pt --network xp \
  xpkg.crossplane.io/crossplane-contrib/function-patch-and-transform:v0.11.2 --insecure
xp composition render ejemplo.yaml composition-basedatos-aws.yaml laboratorio/funcion-render.yaml \
  --xrd=xrd-basedatos.yaml --crossplane-binary=bin/crossplane-core
```

`--crossplane-image` evita que `validate` descargue la imagen `stable`, que no está fijada. `--xrd` hace que
el render aplique los valores por defecto de la API: sin él faltan `engineVersion` y `multiAz`.
`laboratorio/funcion-render.yaml` le dice al render que la función ya está corriendo en `fn-pt:9443`. Sin
esa anotación, `render` arranca la función por su cuenta y necesita el socket de Docker.
