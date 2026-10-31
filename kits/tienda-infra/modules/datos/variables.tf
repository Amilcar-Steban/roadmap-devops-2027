variable "nombre" {
  description = "Prefijo de los recursos, por ejemplo tienda-prod."
  type        = string
}

variable "vpc_id" {
  description = "VPC donde se crean los security groups."
  type        = string
}

variable "subredes_datos" {
  description = "Subredes de datos (sin salida a internet), al menos dos AZ."
  type        = list(string)
  validation {
    condition     = length(var.subredes_datos) >= 2
    error_message = "RDS y ElastiCache necesitan subredes en al menos dos AZ."
  }
}

variable "prefijo_ssm" {
  description = "Ruta de Parameter Store donde se publican los datos de conexión para otras capas."
  type        = string
}

variable "clase_bd" {
  description = "Clase de instancia de RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "version_postgres" {
  description = "Versión mayor de PostgreSQL."
  type        = string
  default     = "17"
}

variable "almacenamiento_gb" {
  description = "Almacenamiento inicial; crece solo hasta 5 veces este valor."
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Réplica en espera en otra AZ (failover automático). Duplica el coste."
  type        = bool
  default     = false
}

variable "retencion_backups" {
  description = "Días de backups automáticos (0 los desactiva)."
  type        = number
  default     = 7
  validation {
    condition     = var.retencion_backups >= 1 && var.retencion_backups <= 35
    error_message = "La retención debe estar entre 1 y 35 días."
  }
}

variable "proteccion_borrado" {
  description = "deletion_protection de AWS y snapshot final al destruir. Actívalo en producción."
  type        = bool
  default     = true
}

variable "nodo_cache" {
  description = "Tipo de nodo de ElastiCache."
  type        = string
  default     = "cache.t4g.micro"
}

variable "replicas_cache" {
  description = "Réplicas de la caché en otras AZ (0 en dev). Con 1 o más hay failover automático."
  type        = number
  default     = 0
}
