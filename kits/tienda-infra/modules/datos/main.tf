# Datos de la tienda: PostgreSQL en RDS y Valkey en ElastiCache, en las subredes de datos.
# Ninguna contraseña pasa por Terraform: RDS la genera, la guarda en Secrets Manager y la rota.

# Quien lleve este security group puede hablar con la base y la caché. La capa app lo adjunta
# a sus tareas: así datos no necesita conocer app (y no hay dependencia circular).
resource "aws_security_group" "clientes" {
  name        = "${var.nombre}-clientes-datos"
  description = "Clientes autorizados de la base de datos y la cache"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "clientes_bd" {
  security_group_id            = aws_security_group.clientes.id
  description                  = "PostgreSQL"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.bd.id
}

resource "aws_vpc_security_group_egress_rule" "clientes_cache" {
  security_group_id            = aws_security_group.clientes.id
  description                  = "Valkey"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.cache.id
}

# --- PostgreSQL

resource "aws_security_group" "bd" {
  name        = "${var.nombre}-bd"
  description = "PostgreSQL de la tienda"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "bd" {
  security_group_id            = aws_security_group.bd.id
  description                  = "PostgreSQL desde los clientes autorizados"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.clientes.id
}

resource "aws_db_subnet_group" "this" {
  name       = var.nombre
  subnet_ids = var.subredes_datos
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.nombre}-pg${var.version_postgres}"
  family = "postgres${var.version_postgres}"

  parameter {
    name  = "rds.force_ssl" # rechaza conexiones sin TLS
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement" # consultas de más de 500 ms al log
    value = "500"
  }

  lifecycle {
    create_before_destroy = true # al cambiar de versión mayor se crea el nuevo grupo antes de borrar el viejo
  }
}

resource "aws_db_instance" "this" {
  identifier     = var.nombre
  engine         = "postgres"
  engine_version = var.version_postgres
  instance_class = var.clase_bd

  db_name                     = "app"
  username                    = "app"
  manage_master_user_password = true # contraseña en Secrets Manager, con rotación; nunca en el estado

  allocated_storage     = var.almacenamiento_gb
  max_allocated_storage = var.almacenamiento_gb * 5
  storage_type          = "gp3"
  storage_encrypted     = true

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.bd.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false

  backup_retention_period         = var.retencion_backups
  copy_tags_to_snapshot           = true
  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
  performance_insights_enabled    = true
  # Permite que otros servicios entren con un token de IAM en lugar de una contraseña
  iam_database_authentication_enabled = true

  deletion_protection       = var.proteccion_borrado
  skip_final_snapshot       = !var.proteccion_borrado
  final_snapshot_identifier = var.proteccion_borrado ? "${var.nombre}-final" : null

  # prevent_destroy no admite variables: si lo quieres solo en prod, deletion_protection
  # (que AWS hace cumplir, también fuera de Terraform) es la protección parametrizable.
}

# --- Valkey (compatible con Redis)

resource "aws_security_group" "cache" {
  name        = "${var.nombre}-cache"
  description = "Valkey de la tienda"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "cache" {
  security_group_id            = aws_security_group.cache.id
  description                  = "Valkey desde los clientes autorizados"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.clientes.id
}

resource "aws_elasticache_subnet_group" "this" {
  name       = var.nombre
  subnet_ids = var.subredes_datos
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.nombre
  description          = "Cache de la tienda"
  engine               = "valkey"
  engine_version       = "8.1"
  node_type            = var.nodo_cache
  port                 = 6379

  num_cache_clusters         = 1 + var.replicas_cache
  automatic_failover_enabled = var.replicas_cache > 0
  multi_az_enabled           = var.replicas_cache > 0

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.cache.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true # la API debe usar rediss://
  snapshot_retention_limit   = var.replicas_cache > 0 ? 3 : 0
  apply_immediately          = !var.proteccion_borrado
}

# --- Lo que otras capas necesitan, publicado en Parameter Store

locals {
  publicado = {
    endpoint_bd    = aws_db_instance.this.address
    secreto_bd_arn = one(aws_db_instance.this.master_user_secret[*].secret_arn)
    endpoint_cache = aws_elasticache_replication_group.this.primary_endpoint_address
    sg_clientes_id = aws_security_group.clientes.id
    bd_nombre      = aws_db_instance.this.db_name
    bd_usuario     = aws_db_instance.this.username
  }
}

resource "aws_ssm_parameter" "publicado" {
  for_each = local.publicado
  name     = "${var.prefijo_ssm}/${each.key}"
  type     = "String" # no son secretos: el secreto está en Secrets Manager, aquí solo su ARN
  value    = each.value
}
