variable "nombre" {
  description = "Nombre global del bucket (minúsculas, números, puntos y guiones)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.nombre))
    error_message = "El nombre debe tener 3-63 caracteres: minúsculas, números, puntos y guiones."
  }
}

variable "versionado" {
  description = "Guardar versiones anteriores de cada objeto."
  type        = bool
  default     = true
}

variable "dias_versiones_antiguas" {
  description = "Días que se conservan las versiones no actuales antes de borrarlas."
  type        = number
  default     = 30
}

variable "forzar_borrado" {
  description = "Permite destruir el bucket aunque tenga objetos. Solo para entornos de prueba."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Clave KMS propia. Si es null, se cifra con claves de S3 (SSE-S3)."
  type        = string
  default     = null
}

variable "politicas_adicionales" {
  description = "Documentos JSON de política que se combinan con la política base (solo TLS)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Etiquetas adicionales."
  type        = map(string)
  default     = {}
}
