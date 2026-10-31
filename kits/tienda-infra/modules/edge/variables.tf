variable "nombre" {
  description = "Prefijo de los recursos, por ejemplo tienda-prod."
  type        = string
}

variable "bucket_web" {
  description = "Nombre global del bucket del frontend."
  type        = string
}

variable "alb_dns" {
  description = "DNS del balanceador de la capa app (origen de /api/*)."
  type        = string
}

variable "alb_https" {
  description = "true si el balanceador tiene certificado y CloudFront debe hablarle por HTTPS."
  type        = bool
  default     = false
}

variable "alias" {
  description = "Dominios propios (requieren certificado_arn en us-east-1)."
  type        = list(string)
  default     = []
}

variable "certificado_arn" {
  description = "Certificado de ACM en us-east-1 para los alias. Si es null, se usa el dominio de CloudFront."
  type        = string
  default     = null
  validation {
    condition     = var.certificado_arn == null || startswith(coalesce(var.certificado_arn, "x"), "arn:aws:acm:us-east-1:")
    error_message = "CloudFront solo acepta certificados de ACM creados en us-east-1."
  }
}

variable "waf_arn" {
  description = "Web ACL de WAF (ámbito CLOUDFRONT). Recomendado en producción."
  type        = string
  default     = null
}

variable "clase_precio" {
  description = "PriceClass_100 (Norteamérica y Europa, la más barata), PriceClass_200 o PriceClass_All."
  type        = string
  default     = "PriceClass_100"
}

variable "forzar_borrado" {
  description = "Permite destruir el bucket del frontend con objetos dentro (solo dev)."
  type        = bool
  default     = false
}
