output "endpoint_bd" {
  description = "Host de PostgreSQL."
  value       = aws_db_instance.this.address
}

output "secreto_bd_arn" {
  description = "ARN del secreto que gestiona RDS (JSON con username y password)."
  value       = local.publicado.secreto_bd_arn
}

output "endpoint_cache" {
  description = "Endpoint primario de Valkey (usa rediss://)."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "sg_clientes_id" {
  description = "Security group que deben llevar los clientes de la base y la caché."
  value       = aws_security_group.clientes.id
}
