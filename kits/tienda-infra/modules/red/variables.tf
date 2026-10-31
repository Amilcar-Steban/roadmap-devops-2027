variable "nombre" {
  description = "Prefijo de los recursos, por ejemplo tienda-prod."
  type        = string
}

variable "cidr" {
  description = "Bloque CIDR de la VPC. Un /16 deja sitio para crecer."
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.cidr, 0)) && tonumber(split("/", var.cidr)[1]) <= 16
    error_message = "cidr debe ser un bloque CIDR válido de tamaño /16 o mayor."
  }
}

variable "azs" {
  description = "Zonas de disponibilidad (entre 2 y 5)."
  type        = list(string)
  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 5 && length(distinct(var.azs)) == length(var.azs)
    error_message = "Indica entre 2 y 5 zonas de disponibilidad distintas."
  }
}

variable "nat" {
  description = "NAT Gateways: ninguno (sin salida a internet), uno (barato, un punto de fallo) o por_az (alta disponibilidad)."
  type        = string
  default     = "uno"
  validation {
    condition     = contains(["ninguno", "uno", "por_az"], var.nat)
    error_message = "nat debe ser ninguno, uno o por_az."
  }
}

variable "flow_logs" {
  description = "Registrar el tráfico de la VPC en CloudWatch Logs."
  type        = bool
  default     = true
}

variable "retencion_logs" {
  description = "Días de retención de los flow logs."
  type        = number
  default     = 14
}
