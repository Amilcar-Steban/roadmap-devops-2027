output "vpc_id" {
  description = "ID de la VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR de la VPC."
  value       = aws_vpc.this.cidr_block
}

output "subredes_publicas" {
  description = "IDs de las subredes públicas, en el orden de var.azs."
  value       = [for az in var.azs : aws_subnet.publica[az].id]
}

output "subredes_privadas" {
  description = "IDs de las subredes privadas, en el orden de var.azs."
  value       = [for az in var.azs : aws_subnet.privada[az].id]
}

output "subredes_datos" {
  description = "IDs de las subredes de datos, en el orden de var.azs."
  value       = [for az in var.azs : aws_subnet.datos[az].id]
}

output "ips_nat" {
  description = "IPs públicas de salida (para listas blancas de terceros)."
  value       = [for e in aws_eip.nat : e.public_ip]
}
