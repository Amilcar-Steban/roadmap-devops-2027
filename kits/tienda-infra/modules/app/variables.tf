variable "nombre" {
  description = "Prefijo de los recursos, por ejemplo tienda-prod."
  type        = string
}

variable "vpc_id" {
  description = "VPC del servicio."
  type        = string
}

variable "subredes_publicas" {
  description = "Subredes del balanceador."
  type        = list(string)
}

variable "subredes_privadas" {
  description = "Subredes de las tareas (sin IP pública)."
  type        = list(string)
}

variable "security_groups_extra" {
  description = "Security groups adicionales para las tareas, como el de clientes de la capa datos."
  type        = list(string)
  default     = []
}

variable "imagen" {
  description = "Imagen inicial. Después la actualiza el pipeline de la Fase 3 (Terraform ignora ese cambio)."
  type        = string
}

variable "puerto" {
  description = "Puerto del contenedor."
  type        = number
  default     = 8000
}

variable "ruta_salud" {
  description = "Ruta del health check del balanceador."
  type        = string
  default     = "/health"
}

variable "cpu" {
  description = "Unidades de CPU de la tarea (1024 = 1 vCPU)."
  type        = number
  default     = 512
}

variable "memoria" {
  description = "Memoria de la tarea en MiB."
  type        = number
  default     = 1024
}

variable "tareas_min" {
  description = "Tareas mínimas del autoescalado."
  type        = number
  default     = 1
}

variable "tareas_max" {
  description = "Tareas máximas del autoescalado."
  type        = number
  default     = 2
  validation {
    condition     = var.tareas_max >= var.tareas_min
    error_message = "tareas_max no puede ser menor que tareas_min."
  }
}

variable "cpu_objetivo" {
  description = "Porcentaje de CPU que el autoescalado intenta mantener."
  type        = number
  default     = 60
}

variable "variables_entorno" {
  description = "Variables de entorno del contenedor."
  type        = map(string)
  default     = {}
}

variable "secretos" {
  description = "Variables que ECS lee de Secrets Manager: nombre => valueFrom (ARN, con :clave:: para JSON)."
  type        = map(string)
  default     = {}
}

variable "secretos_arn" {
  description = "ARNs de los secretos que el rol de ejecución puede leer."
  type        = list(string)
  default     = []
}

variable "certificado_arn" {
  description = "Certificado de ACM para HTTPS en el balanceador. Si es null, solo HTTP (detrás de CloudFront)."
  type        = string
  default     = null
}

variable "proteccion_borrado" {
  description = "Protección contra borrado del balanceador."
  type        = bool
  default     = false
}

variable "retencion_logs" {
  description = "Días de retención de los logs del contenedor."
  type        = number
  default     = 14
}
